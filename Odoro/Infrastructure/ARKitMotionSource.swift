//
//  ARKitMotionSource.swift
//  Odoro
//

import ARKit
import Foundation
import os
import RealityKit

final class ARKitMotionSource: NSObject, MotionSource {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "ARKitMotionSource")
    private let previewOverlayFrameInterval = 15

    var captureMode: CaptureMode { .rearBody3D }
    var onFrame: ((MotionFrame) -> Void)?
    var onStatusTextChange: ((String) -> Void)?

    var isSupported: Bool {
        ARBodyTrackingConfiguration.isSupported
    }

    private let session = ARSession()
    private let overlayRenderer = ARKitCaptureOverlayRenderer()
    private let liveFrameValidator = ARKitLiveCaptureFrameValidator()
    private weak var attachedView: ARView?
    private var desiredActivity: MotionSourceActivity = .preview
    private var shouldStartWhenAttached = false
    private var hasDetectedBody = false
    private var isSessionActive = false
    private var previewOverlayFrameCounter = 0

    func attach(to view: ARView) {
        attachedView = view
        view.session = session
        session.delegate = self
        overlayRenderer.attach(to: view)
        overlayRenderer.setDetailLevel(detailLevel(for: desiredActivity))

        if shouldStartWhenAttached {
            shouldStartWhenAttached = false
            activate(for: desiredActivity)
        }
    }

    func activate(for activity: MotionSourceActivity) {
        desiredActivity = activity
        overlayRenderer.setDetailLevel(detailLevel(for: activity))
        previewOverlayFrameCounter = 0

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
        configuration.automaticSkeletonScaleEstimationEnabled = false
        hasDetectedBody = false
        isSessionActive = true
        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }

    func deactivate() {
        previewOverlayFrameCounter = 0
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
            let validation = self.liveFrameValidator.validate(frame)
            guard validation.isValid else {
                Self.logger.debug("Skipping implausible ARKit body frame: \(validation.rejectionReason ?? "unknown reason", privacy: .public)")
                return
            }

            if !self.hasDetectedBody {
                self.hasDetectedBody = true
                self.onStatusTextChange?(L10n.statusBodyDetected)
            }

            if self.shouldRenderOverlayFrame() {
                self.overlayRenderer.render(frame: frame)
            }

            if self.desiredActivity == .recording {
                self.onFrame?(frame)
            }
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

private extension ARKitMotionSource {
    func detailLevel(for activity: MotionSourceActivity) -> ARKitCaptureOverlayRenderer.DetailLevel {
        switch activity {
        case .preview:
            .preview
        case .recording:
            .recording
        }
    }

    func shouldRenderOverlayFrame() -> Bool {
        switch desiredActivity {
        case .recording:
            return true
        case .preview:
            previewOverlayFrameCounter = (previewOverlayFrameCounter + 1) % previewOverlayFrameInterval
            return previewOverlayFrameCounter == 0
        }
    }
}
