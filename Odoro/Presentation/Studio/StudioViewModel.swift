//
//  StudioViewModel.swift
//

import ARKit
import Combine
import Foundation
import RealityKit
import UIKit

@MainActor
final class StudioViewModel: ObservableObject {
    @Published var state = MotionStudioState()
    @Published var captureMode: CaptureMode
    @Published var recordingContext: MotionRecordingContext
    @Published var currentSessionTakes: [MotionTakeSummary] = []
    @Published var libraryClips: [MotionTakeSummary] = []
    @Published var currentTakeID: UUID?
    @Published var screen: StudioScreen = .capture
    @Published var screenTransition: StudioScreenTransition = .fromTrailing
    @Published var swipeHintsVisible = false
    @Published var availableAvatarOptions: [StageAvatarOption] = AvatarCatalog.builtInStageOptions
    @Published var selectedAvatarOption: StageAvatarOption = AvatarCatalog.defaultOption
    @Published var transientMessage: String?
    @Published var isImportingVideo = false
    @Published var isImportingAvatar = false
    @Published var previewingAudioSourceID: String?

    let supportedCaptureModes: [CaptureMode]
    let videoImporter = VideoMotionImporter()
    let maximumImportedVideoDuration: TimeInterval = 10
    let audioPlaybackController: StudioAudioPlaybackControlling
    let archiveStore: MotionArchiveStore?
    let avatarAssetStore: AvatarAssetStore
    let motionSourceFactory: (CaptureMode) -> MotionSource
    var source: MotionSource
    var interactor: MotionStudioInteractor
    let stageRenderer = StagePlaybackRenderer()
    weak var attachedCaptureARView: ARView?
    weak var attachedFrontPreviewView: UIView?
    var currentSessionID: UUID?
    var swipeHintDismissTask: Task<Void, Never>?
    var transientMessageDismissTask: Task<Void, Never>?

    init(
        archiveStore: MotionArchiveStore? = nil,
        recordingContext: MotionRecordingContext? = nil,
        audioPlaybackController: StudioAudioPlaybackControlling? = nil,
        avatarAssetStore: AvatarAssetStore? = nil,
        motionSourceFactory: ((CaptureMode) -> MotionSource)? = nil
    ) {
        let modes = Self.makeSupportedCaptureModes()
        let initialMode = Self.defaultCaptureMode(from: modes)
        let resolvedMotionSourceFactory = motionSourceFactory ?? Self.makeMotionSource
        let source = resolvedMotionSourceFactory(initialMode)
        let normalizedRecordingContext = Self.normalizedRecordingContext(recordingContext ?? .defaultMetronomeLoop)

        self.supportedCaptureModes = modes
        self.audioPlaybackController = audioPlaybackController ?? StudioAudioPlaybackController()
        self.archiveStore = archiveStore
        self.avatarAssetStore = avatarAssetStore ?? AvatarAssetStore()
        self.motionSourceFactory = resolvedMotionSourceFactory
        self.recordingContext = normalizedRecordingContext
        self.captureMode = initialMode
        self.source = source
        self.interactor = MotionStudioInteractor(
            source: source,
            maximumCaptureDuration: normalizedRecordingContext.fixedCaptureDuration
        )

        configureForCurrentSource()
        refreshLibrary()
        refreshAvatarLibrary()
    }

    func configureForCurrentSource() {
        stageRenderer.setUsesProceduralMockPlayback(source is MockMotionSource)
        stageRenderer.setAvatarOption(selectedAvatarOption)

        interactor.onStateChange = { [weak self] newState in
            self?.handleInteractorStateChange(newState)
        }

        interactor.onClipChange = { [weak self] clip in
            self?.stageRenderer.setClip(clip)
        }
    }

    func handleInteractorStateChange(_ newState: MotionStudioState) {
        let previousState = state
        state = newState

        if previousState.isRecording, !newState.isRecording {
            stopAudioPlayback()
        }

        if previousState.presentation != .stage, newState.presentation == .stage {
            if previousState.isRecording {
                persistCurrentClipIfPossible()
                refreshLibrary()
            }

            prepareStagePlayback()
            navigate(to: .stage, transition: .fromLeading)
        }
    }

    static func defaultCaptureMode(from modes: [CaptureMode]) -> CaptureMode {
        modes.first ?? .mock
    }

    static func normalizedRecordingContext(_ context: MotionRecordingContext) -> MotionRecordingContext {
        context.normalizedForFixedCaptureLength()
    }
}
