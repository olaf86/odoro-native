//
//  VisionFrontCameraMotionSource.swift
//  Odoro
//

import AVFoundation
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
        previewLayer.session = nil
        previewLayer.removeFromSuperlayer()
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
        VisionBodyPoseFrameBuilder.makeFrame(from: observation, at: time)
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
