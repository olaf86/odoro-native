//
//  ARKitMotionSource.swift
//  Odoro
//

import ARKit
import Foundation
import RealityKit

final class ARKitMotionSource: NSObject, MotionSource {
    var captureMode: CaptureMode { .rearBody3D }
    var onFrame: ((MotionFrame) -> Void)?
    var onStatusTextChange: ((String) -> Void)?

    var isSupported: Bool {
        ARBodyTrackingConfiguration.isSupported
    }

    private let session = ARSession()
    private let overlayRenderer = ARKitCaptureOverlayRenderer()
    private weak var attachedView: ARView?
    private var shouldStartWhenAttached = false
    private var hasDetectedBody = false
    private var isSessionActive = false

    func attach(to view: ARView) {
        attachedView = view
        view.session = session
        session.delegate = self
        overlayRenderer.attach(to: view)

        if shouldStartWhenAttached {
            shouldStartWhenAttached = false
            activate()
        }
    }

    func activate() {
        guard isSupported else {
            onStatusTextChange?(L10n.statusARUnsupported)
            return
        }

        guard attachedView != nil else {
            shouldStartWhenAttached = true
            onStatusTextChange?(L10n.statusARPreparingPreview)
            return
        }

        guard !isSessionActive else {
            return
        }

        let configuration = ARBodyTrackingConfiguration()
        configuration.isAutoFocusEnabled = true
        configuration.automaticSkeletonScaleEstimationEnabled = true
        hasDetectedBody = false
        isSessionActive = true
        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }

    func deactivate() {
        hasDetectedBody = false
        isSessionActive = false
        session.pause()
        overlayRenderer.clear()
    }

    nonisolated private static func makeFrame(from bodyAnchor: ARBodyAnchor, timestamp: TimeInterval) -> MotionFrame {
        let worldTransform = bodyAnchor.transform
        let jointTransforms = bodyAnchor.skeleton.jointModelTransforms.map { jointTransform in
            simd_mul(worldTransform, jointTransform)
        }
        let positions = jointTransforms.map { finalTransform in
            let translation = finalTransform.columns.3
            return SIMD3<Float>(translation.x, translation.y, translation.z)
        }
        let rotations = jointTransforms.map { transform in
            Optional(MotionJointRotation(simd_quaternion(transform)))
        }

        return MotionFrame(
            time: timestamp,
            jointPositions: positions,
            jointRotations: rotations
        )
    }
}

extension ARKitMotionSource: ARSessionDelegate {
    nonisolated func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        guard let bodyAnchor = anchors.compactMap({ $0 as? ARBodyAnchor }).first else {
            return
        }

        let timestamp = session.currentFrame?.timestamp ?? ProcessInfo.processInfo.systemUptime
        let frame = Self.makeFrame(from: bodyAnchor, timestamp: timestamp)
        Task { @MainActor in
            if !self.hasDetectedBody {
                self.hasDetectedBody = true
                self.onStatusTextChange?(L10n.statusBodyDetected)
            }
            self.overlayRenderer.render(frame: frame)
            self.onFrame?(frame)
        }
    }

    nonisolated func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
        guard anchors.contains(where: { $0 is ARBodyAnchor }) else {
            return
        }

        Task { @MainActor in
            self.hasDetectedBody = false
            self.overlayRenderer.clear()
            self.onStatusTextChange?(L10n.statusStandInFrame)
        }
    }

    nonisolated func session(_ session: ARSession, didFailWithError error: any Error) {
        Task { @MainActor in
            self.isSessionActive = false
            self.overlayRenderer.clear()
            self.onStatusTextChange?(L10n.statusARSessionFailed(error.localizedDescription))
        }
    }

    nonisolated func sessionWasInterrupted(_ session: ARSession) {
        Task { @MainActor in
            self.hasDetectedBody = false
            self.overlayRenderer.clear()
            self.onStatusTextChange?(L10n.statusARInterrupted)
        }
    }

    nonisolated func sessionInterruptionEnded(_ session: ARSession) {
        Task { @MainActor in
            self.hasDetectedBody = false
            self.overlayRenderer.clear()
            self.onStatusTextChange?(L10n.statusARResumed)
        }
    }
}
