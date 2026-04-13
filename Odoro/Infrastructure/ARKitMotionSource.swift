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
    private weak var attachedView: ARView?
    private var shouldStartWhenAttached = false

    func attach(to view: ARView) {
        attachedView = view
        view.session = session
        session.delegate = self

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

        let configuration = ARBodyTrackingConfiguration()
        configuration.isAutoFocusEnabled = true
        configuration.automaticSkeletonScaleEstimationEnabled = true
        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }

    func deactivate() {
        session.pause()
    }

    nonisolated private static func makeFrame(from bodyAnchor: ARBodyAnchor, timestamp: TimeInterval) -> MotionFrame {
        let worldTransform = bodyAnchor.transform
        let positions = bodyAnchor.skeleton.jointModelTransforms.map { jointTransform in
            let finalTransform = simd_mul(worldTransform, jointTransform)
            let translation = finalTransform.columns.3
            return SIMD3<Float>(translation.x, translation.y, translation.z)
        }

        return MotionFrame(time: timestamp, jointPositions: positions)
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
            self.onFrame?(frame)
        }
    }

    nonisolated func session(_ session: ARSession, didFailWithError error: any Error) {
        Task { @MainActor in
            self.onStatusTextChange?(L10n.statusARSessionFailed(error.localizedDescription))
        }
    }

    nonisolated func sessionWasInterrupted(_ session: ARSession) {
        Task { @MainActor in
            self.onStatusTextChange?(L10n.statusARInterrupted)
        }
    }

    nonisolated func sessionInterruptionEnded(_ session: ARSession) {
        Task { @MainActor in
            self.onStatusTextChange?(L10n.statusARResumed)
        }
    }
}
