//
//  StudioViewModel.swift
//  Visco
//

import ARKit
import Combine
import Foundation
import RealityKit
import UIKit

@MainActor
final class StudioViewModel: ObservableObject {
    @Published private(set) var state = MotionStudioState()
    @Published private(set) var captureMode: CaptureMode

    var presentation: StudioPresentation { state.presentation }
    var statusText: String { state.statusText }
    var isRecording: Bool { state.isRecording }
    var isPlaying: Bool { state.isPlaying }
    var recordedFrameCount: Int { state.recordedFrameCount }
    var hasClip: Bool { state.hasClip }
    var availableCaptureModes: [CaptureMode] { supportedCaptureModes }

    var recordingDurationText: String {
        state.recordingDuration.formatted(.number.precision(.fractionLength(1))) + "s"
    }

    var clipDurationText: String {
        state.clipDuration.formatted(.number.precision(.fractionLength(1))) + "s clip"
    }

    var usesMockSource: Bool {
        source.captureMode == .mock
    }

    var usesFrontCameraSource: Bool {
        source.captureMode == .frontUpperBody
    }

    private let supportedCaptureModes: [CaptureMode]
    private var source: MotionSource
    private var interactor: MotionStudioInteractor
    private let stageRenderer = StagePlaybackRenderer()
    private weak var attachedCaptureARView: ARView?
    private weak var attachedFrontPreviewView: UIView?

    init() {
        let modes = Self.makeSupportedCaptureModes()
        let initialMode = Self.defaultCaptureMode(from: modes)
        let source = Self.makeMotionSource(for: initialMode)

        self.supportedCaptureModes = modes
        self.captureMode = initialMode
        self.source = source
        self.interactor = MotionStudioInteractor(source: source)

        configureForCurrentSource()
        interactor.startSource()
    }

    func beginRecording() {
        interactor.beginRecording()
    }

    func stopRecording() {
        interactor.stopRecording()
        if state.presentation == .stage {
            prepareStagePlayback()
        }
    }

    func enterStageMode() {
        interactor.enterStageMode()
        prepareStagePlayback()
    }

    func returnToCapture() {
        stageRenderer.pause()
        interactor.setPlaybackActive(false)
        interactor.returnToCapture()
        interactor.startSource()
    }

    func resetClip() {
        stageRenderer.pause()
        interactor.setPlaybackActive(false)
        stageRenderer.setClip(nil)
        interactor.resetClip()
    }

    func prepareStagePlayback() {
        interactor.stopSource()
        stageRenderer.setClip(interactor.currentClip)
        stageRenderer.play()
        interactor.setPlaybackActive(true)
    }

    func pausePlayback() {
        stageRenderer.pause()
        interactor.setPlaybackActive(false)
    }

    func togglePlayback() {
        if state.isPlaying {
            pausePlayback()
        } else {
            prepareStagePlayback()
        }
    }

    func selectCaptureMode(_ mode: CaptureMode) {
        guard captureMode != mode, !state.isRecording else { return }

        stageRenderer.pause()
        stageRenderer.setClip(nil)
        interactor.stopSource()

        captureMode = mode
        source = Self.makeMotionSource(for: mode)
        interactor = MotionStudioInteractor(source: source)
        state = MotionStudioState(statusText: mode.descriptionText)

        configureForCurrentSource()
        attachCurrentSourceIfPossible()
        interactor.startSource()
    }

    func attachCaptureView(_ view: ARView) {
        attachedCaptureARView = view
        (source as? ARKitMotionSource)?.attach(to: view)
        interactor.startSource()
    }

    func attachFrontCaptureView(_ view: UIView) {
        attachedFrontPreviewView = view
        (source as? VisionFrontCameraMotionSource)?.attachPreview(to: view)
        interactor.startSource()
    }

    func updateFrontCapturePreview(in view: UIView) {
        (source as? VisionFrontCameraMotionSource)?.updatePreviewFrame(to: view.bounds)
    }

    func attachStageView(_ view: ARView) {
        stageRenderer.attach(to: view)
        stageRenderer.setClip(interactor.currentClip)
    }

    private func configureForCurrentSource() {
        stageRenderer.setUsesProceduralMockPlayback(source is MockMotionSource)

        interactor.onStateChange = { [weak self] state in
            self?.state = state
        }

        interactor.onClipChange = { [weak self] clip in
            self?.stageRenderer.setClip(clip)
        }
    }

    private func attachCurrentSourceIfPossible() {
        if let arView = attachedCaptureARView {
            (source as? ARKitMotionSource)?.attach(to: arView)
        }

        if let previewView = attachedFrontPreviewView {
            (source as? VisionFrontCameraMotionSource)?.attachPreview(to: previewView)
        }
    }

    private static func makeSupportedCaptureModes() -> [CaptureMode] {
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

    private static func defaultCaptureMode(from modes: [CaptureMode]) -> CaptureMode {
        modes.first ?? .mock
    }

    private static func makeMotionSource(for mode: CaptureMode) -> MotionSource {
        switch mode {
        case .rearBody3D:
            ARKitMotionSource()
        case .frontUpperBody:
            VisionFrontCameraMotionSource()
        case .mock:
            MockMotionSource()
        }
    }
}
