//
//  StudioViewModel+Capture.swift
//  Odoro
//

import ARKit
import Foundation
import RealityKit
import UIKit

extension StudioViewModel {
    func beginRecording() {
        guard screen == .capture else {
            navigate(to: .capture, transition: .fromTrailing)
            return
        }

        dismissSwipeHints()
        stopAudioPreview()
        attachCurrentSourceIfPossible()
        interactor.activateSource()
        interactor.beginRecording()
        startRecordingAudioIfNeeded()
    }

    func stopRecording() {
        stopAudioPlayback()
        interactor.stopRecording()
    }

    func enterStageMode() {
        interactor.enterStageMode()
    }

    func selectCaptureMode(_ mode: CaptureMode) {
        guard captureMode != mode, !state.isRecording else { return }

        stopAudioPlayback()
        stageRenderer.pause()
        stageRenderer.setClip(nil)
        interactor.deactivateSource()

        captureMode = mode
        source = motionSourceFactory(mode)
        interactor = MotionStudioInteractor(
            source: source,
            maximumCaptureDuration: recordingContext.fixedCaptureDuration,
            capturedClipPreparer: Self.makeCapturedClipPreparer(for: mode)
        )
        state = MotionStudioState(statusText: mode.descriptionText)
        currentSessionID = nil
        currentTakeID = nil
        currentSessionTakes = []

        configureForCurrentSource()
        attachCurrentSourceIfPossible()
        interactor.activateSource()
        navigate(to: .capture, transition: .fromTrailing)
    }

    func attachCaptureView(_ view: ARView) {
        capturePreviewAttachments.attachCaptureView(view, to: source)
    }

    func attachFrontCaptureView(_ view: UIView) {
        capturePreviewAttachments.attachFrontPreviewView(view, to: source)
    }

    func updateFrontCapturePreview(in view: UIView) {
        capturePreviewAttachments.updateFrontPreviewFrame(in: view, source: source)
    }

    func prepareCapturePreviewIfNeeded() {
        guard screen == .capture else {
            return
        }

        attachCurrentSourceIfPossible()
        interactor.activateSource()
    }

    func suspendStudioForInactivity() {
        stopAudioPlayback()
        stageRenderer.pause()
        interactor.setPlaybackActive(false)
        interactor.suspendForAppInactivity()
    }

    func attachCurrentSourceIfPossible() {
        capturePreviewAttachments.attachCurrentSourceIfPossible(source)
    }

    static func makeSupportedCaptureModes() -> [CaptureMode] {
        var modes: [CaptureMode] = []

        #if targetEnvironment(simulator)
        modes = [.mock]
        #else
        if ARBodyTrackingConfiguration.isSupported {
            modes.append(.rearBody3D)
        }

        if VisionFrontCameraMotionSource().isSupported {
            modes.append(.frontUpperBody)
        }

        modes.append(.mock)
        #endif

        return modes
    }

    static func makeMotionSource(for mode: CaptureMode) -> MotionSource {
        switch mode {
        case .rearBody3D:
            ARKitMotionSource()
        case .frontUpperBody:
            VisionFrontCameraMotionSource()
        case .importedVideo:
            MockMotionSource()
        case .mock:
            MockMotionSource()
        }
    }
}
