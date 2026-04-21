//
//  StudioViewModel.swift
//

import Combine
import Foundation

@MainActor
final class StudioViewModel: ObservableObject {
    // MARK: - Published State

    @Published var state = MotionStudioState()
    @Published var captureMode: CaptureMode
    @Published var recordingContext: MotionRecordingContext
    @Published var currentSessionTakes: [MotionTakeSummary] = []
    @Published var libraryClips: [MotionTakeSummary] = []
    @Published var currentTakeID: UUID?

    // MARK: - Navigation

    @Published var screen: StudioScreen = .capture
    @Published var screenTransition: StudioScreenTransition = .fromTrailing
    @Published var swipeHintsVisible = false

    // MARK: - Stage Assets

    @Published var availableAvatarOptions: [StageAvatarOption] = AvatarCatalog.builtInStageOptions
    @Published var selectedAvatarOption: StageAvatarOption = AvatarCatalog.defaultOption

    // MARK: - Transient UI

    @Published var transientMessage: String?
    @Published var isImportingVideo = false
    @Published var isImportingAvatar = false
    @Published var previewingAudioSourceID: String?

    // MARK: - Dependencies

    let supportedCaptureModes: [CaptureMode]
    let videoImporter = VideoMotionImporter()
    let maximumImportedVideoDuration: TimeInterval = 10
    let audioPlaybackController: StudioAudioPlaybackControlling
    let archiveStore: MotionArchiveStore?
    let avatarAssetStore: AvatarAssetStore
    let motionSourceFactory: (CaptureMode) -> MotionSource

    // MARK: - Runtime Collaborators

    var source: MotionSource
    var interactor: MotionStudioInteractor
    let stageRenderer = StagePlaybackRenderer()
    var capturePreviewAttachments = CapturePreviewAttachments()
    var currentSessionID: UUID?
    var swipeHintDismissTask: Task<Void, Never>?
    var transientMessageDismissTask: Task<Void, Never>?

    // MARK: - Initialization

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

    // MARK: - Interactor Binding

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

    // MARK: - Defaults

    static func defaultCaptureMode(from modes: [CaptureMode]) -> CaptureMode {
        modes.first ?? .mock
    }

    static func normalizedRecordingContext(_ context: MotionRecordingContext) -> MotionRecordingContext {
        context.normalizedForFixedCaptureLength()
    }
}
