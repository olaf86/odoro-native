//
//  StudioViewModel.swift
//  Visco
//

import ARKit
import Combine
import Foundation
import RealityKit

@MainActor
final class StudioViewModel: ObservableObject {
    @Published private(set) var state = MotionStudioState()

    var presentation: StudioPresentation { state.presentation }
    var statusText: String { state.statusText }
    var isRecording: Bool { state.isRecording }
    var isPlaying: Bool { state.isPlaying }
    var recordedFrameCount: Int { state.recordedFrameCount }
    var hasClip: Bool { state.hasClip }

    var recordingDurationText: String {
        state.recordingDuration.formatted(.number.precision(.fractionLength(1))) + "s"
    }

    var clipDurationText: String {
        state.clipDuration.formatted(.number.precision(.fractionLength(1))) + "s clip"
    }

    var usesMockSource: Bool {
        source is MockMotionSource
    }

    private let source: MotionSource
    private let interactor: MotionStudioInteractor
    private let stageRenderer = StagePlaybackRenderer()

    init() {
        let source = StudioViewModel.makeMotionSource()
        self.source = source
        self.interactor = MotionStudioInteractor(source: source)
        self.stageRenderer.setUsesProceduralMockPlayback(source is MockMotionSource)

        interactor.onStateChange = { [weak self] state in
            self?.state = state
        }

        interactor.onClipChange = { [weak self] clip in
            self?.stageRenderer.setClip(clip)
        }

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

    func attachCaptureView(_ view: ARView) {
        (source as? ARKitMotionSource)?.attach(to: view)
        interactor.startSource()
    }

    func attachStageView(_ view: ARView) {
        stageRenderer.attach(to: view)
        stageRenderer.setClip(interactor.currentClip)
    }

    private static func makeMotionSource() -> MotionSource {
        #if targetEnvironment(simulator)
        MockMotionSource()
        #else
        if ARBodyTrackingConfiguration.isSupported {
            ARKitMotionSource()
        } else {
            MockMotionSource()
        }
        #endif
    }
}
