//
//  VisionFrontCameraMotionSource.swift
//  Odoro
//

import ARKit
import AVFoundation
import CoreImage
import Foundation
import UIKit
import Vision

final class VisionFrontCameraMotionSource: NSObject, MotionSource {
    private enum PoseStatus {
        case detecting
        case moveIntoFrame
        case ready
    }

    var captureMode: CaptureMode { .frontUpperBody }
    var onFrame: ((MotionFrame) -> Void)?
    var onStatusTextChange: ((String) -> Void)?

    var isSupported: Bool {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) != nil
    }

    private let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let processingQueue = DispatchQueue(label: "Odoro.VisionFrontCameraMotionSource")
    private let skeletonDefinition = ARSkeletonDefinition.defaultBody3D
    private let neutralJointPositions: [SIMD3<Float>] = {
        let neutral = ARSkeletonDefinition.defaultBody3D.neutralBodySkeleton3D?.jointModelTransforms ?? []
        return neutral.map { transform in
            let translation = transform.columns.3
            return SIMD3<Float>(translation.x, translation.y, translation.z)
        }
    }()

    private weak var previewContainerView: UIView?
    private let previewLayer = AVCaptureVideoPreviewLayer()
    private var isConfigured = false
    private var shouldStartWhenAttached = false
    private var permissionRequested = false
    private var poseStatus: PoseStatus?

    func attachPreview(to view: UIView) {
        previewContainerView = view
        previewLayer.session = session
        previewLayer.videoGravity = .resizeAspectFill

        if previewLayer.superlayer !== view.layer {
            previewLayer.removeFromSuperlayer()
            view.layer.insertSublayer(previewLayer, at: 0)
        }

        previewLayer.frame = view.bounds

        if shouldStartWhenAttached {
            shouldStartWhenAttached = false
            activate()
        }
    }

    func updatePreviewFrame(to bounds: CGRect) {
        previewLayer.frame = bounds
    }

    func activate() {
        guard isSupported else {
            onStatusTextChange?(L10n.statusFrontCameraUnsupported)
            return
        }

        guard previewContainerView != nil else {
            shouldStartWhenAttached = true
            onStatusTextChange?(L10n.statusFrontPreparingPreview)
            return
        }

        ensureAuthorizedAndConfigured()
    }

    func deactivate() {
        poseStatus = nil
        session.stopRunning()
    }

    private func ensureAuthorizedAndConfigured() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndRunIfNeeded()
        case .notDetermined:
            guard !permissionRequested else { return }
            permissionRequested = true
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if granted {
                        self.configureAndRunIfNeeded()
                    } else {
                        self.onStatusTextChange?(L10n.statusFrontPermissionDenied)
                    }
                }
            }
        default:
            onStatusTextChange?(L10n.statusFrontPermissionDenied)
        }
    }

    @MainActor
    private func configureAndRunIfNeeded() {
        if !isConfigured {
            do {
                try configureSession()
                isConfigured = true
            } catch {
                onStatusTextChange?(L10n.statusFrontSetupFailed(error.localizedDescription))
                return
            }
        }

        guard !session.isRunning else { return }
        emitStatusIfNeeded(.detecting, text: L10n.statusFrontDetecting)
        processingQueue.async { [weak self] in
            self?.session.startRunning()
        }
    }

    @MainActor
    private func configureSession() throws {
        session.beginConfiguration()
        session.sessionPreset = .high

        for input in session.inputs {
            session.removeInput(input)
        }

        for output in session.outputs {
            session.removeOutput(output)
        }

        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
            session.commitConfiguration()
            throw NSError(domain: "Odoro.VisionFrontCameraMotionSource", code: -1)
        }

        let input = try AVCaptureDeviceInput(device: camera)
        guard session.canAddInput(input) else {
            session.commitConfiguration()
            throw NSError(domain: "Odoro.VisionFrontCameraMotionSource", code: -2)
        }
        session.addInput(input)

        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
        ]
        videoOutput.setSampleBufferDelegate(self, queue: processingQueue)

        guard session.canAddOutput(videoOutput) else {
            session.commitConfiguration()
            throw NSError(domain: "Odoro.VisionFrontCameraMotionSource", code: -3)
        }
        session.addOutput(videoOutput)

        if let connection = videoOutput.connection(with: .video) {
            if connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
            connection.isVideoMirrored = true
        }

        session.commitConfiguration()
    }

    private func makeFrame(from observation: VNHumanBodyPoseObservation, at time: TimeInterval) -> MotionFrame? {
        guard let points = try? observation.recognizedPoints(.all) else {
            return nil
        }

        guard
            let leftShoulder = stagePosition(for: .leftShoulder, in: points),
            let rightShoulder = stagePosition(for: .rightShoulder, in: points)
        else {
            return nil
        }

        let shoulderCenter = (leftShoulder + rightShoulder) * 0.5
        let root = shoulderCenter + SIMD3<Float>(0, -0.30, 0.02)
        let head = stagePosition(for: .nose, in: points) ?? shoulderCenter + SIMD3<Float>(0, 0.26, 0.03)

        let leftElbow = stagePosition(for: .leftElbow, in: points) ?? leftShoulder + SIMD3<Float>(-0.18, -0.18, 0.02)
        let rightElbow = stagePosition(for: .rightElbow, in: points) ?? rightShoulder + SIMD3<Float>(0.18, -0.18, 0.02)
        let leftHand = stagePosition(for: .leftWrist, in: points) ?? leftElbow + SIMD3<Float>(-0.18, -0.14, 0)
        let rightHand = stagePosition(for: .rightWrist, in: points) ?? rightElbow + SIMD3<Float>(0.18, -0.14, 0)

        let leftHip = root + SIMD3<Float>(-0.12, -0.02, 0)
        let rightHip = root + SIMD3<Float>(0.12, -0.02, 0)
        let leftKnee = leftHip + SIMD3<Float>(-0.02, -0.36, 0.04)
        let rightKnee = rightHip + SIMD3<Float>(0.02, -0.36, -0.04)
        let leftFoot = leftKnee + SIMD3<Float>(0, -0.38, 0.05)
        let rightFoot = rightKnee + SIMD3<Float>(0, -0.38, 0.05)

        var joints = neutralJointPositions
        if joints.count != skeletonDefinition.jointNames.count {
            joints = Array(repeating: SIMD3<Float>(0, -10, 0), count: skeletonDefinition.jointNames.count)
        }

        setJoint(.root, to: root, in: &joints)
        setJoint(.head, to: head, in: &joints)
        setJoint(.leftShoulder, to: leftShoulder, in: &joints)
        setJoint(.rightShoulder, to: rightShoulder, in: &joints)
        setJoint(named: "left_arm_joint", to: leftElbow, in: &joints)
        setJoint(named: "right_arm_joint", to: rightElbow, in: &joints)
        setJoint(.leftHand, to: leftHand, in: &joints)
        setJoint(.rightHand, to: rightHand, in: &joints)
        setJoint(named: "left_upLeg_joint", to: leftHip, in: &joints)
        setJoint(named: "right_upLeg_joint", to: rightHip, in: &joints)
        setJoint(named: "left_leg_joint", to: leftKnee, in: &joints)
        setJoint(named: "right_leg_joint", to: rightKnee, in: &joints)
        setJoint(.leftFoot, to: leftFoot, in: &joints)
        setJoint(.rightFoot, to: rightFoot, in: &joints)

        return MotionFrame(time: time, jointPositions: joints)
    }

    private func stagePosition(
        for jointName: VNHumanBodyPoseObservation.JointName,
        in points: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint]
    ) -> SIMD3<Float>? {
        guard let point = points[jointName], point.confidence > 0.15 else {
            return nil
        }

        let x = (Float(point.x) - 0.5) * 1.6
        let y = Float(point.y) * 1.8 + 0.05
        return SIMD3<Float>(x, y, 0)
    }

    private func setJoint(_ jointName: ARSkeleton.JointName, to position: SIMD3<Float>, in joints: inout [SIMD3<Float>]) {
        let index = skeletonDefinition.index(for: jointName)
        guard index != NSNotFound, joints.indices.contains(index) else {
            return
        }
        joints[index] = position
    }

    private func setJoint(named rawValue: String, to position: SIMD3<Float>, in joints: inout [SIMD3<Float>]) {
        setJoint(ARSkeleton.JointName(rawValue: rawValue), to: position, in: &joints)
    }
}

extension VisionFrontCameraMotionSource: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        let request = VNDetectHumanBodyPoseRequest()
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds

        do {
            let handler = VNImageRequestHandler(cmSampleBuffer: sampleBuffer, orientation: .leftMirrored, options: [:])
            try handler.perform([request])
        } catch {
            Task { @MainActor in
                self.onStatusTextChange?(L10n.statusFrontPoseFailed(error.localizedDescription))
            }
            return
        }

        guard let observation = request.results?.first, let frame = makeFrame(from: observation, at: timestamp) else {
            Task { @MainActor in
                self.emitStatusIfNeeded(.moveIntoFrame, text: L10n.statusFrontMoveIntoFrame)
            }
            return
        }

        Task { @MainActor in
            self.emitStatusIfNeeded(.ready, text: L10n.statusFrontReady)
            self.onFrame?(frame)
        }
    }
}

private extension VisionFrontCameraMotionSource {
    private func emitStatusIfNeeded(_ status: PoseStatus, text: String) {
        guard poseStatus != status else {
            return
        }

        poseStatus = status
        onStatusTextChange?(text)
    }
}
