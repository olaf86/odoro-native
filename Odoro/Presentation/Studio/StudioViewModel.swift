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
    @Published var stageDebugMotionViewMode: StageDebugMotionViewMode = .stabilized

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
    let stagePlaybackBuilder = StagePreparedPlaybackBuilder()
    var capturePreviewAttachments = CapturePreviewAttachments()
    var currentSessionID: UUID?
    var swipeHintDismissTask: Task<Void, Never>?
    var transientMessageDismissTask: Task<Void, Never>?
    var playbackCaptureMode: CaptureMode?
    var preparedStagePlayback: StagePreparedPlayback?
    var storedPlaybackArtifacts: MotionPlaybackArtifacts?

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
            maximumCaptureDuration: normalizedRecordingContext.fixedCaptureDuration,
            capturedClipPreparer: Self.makeCapturedClipPreparer(for: initialMode)
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
            self?.rebuildPreparedStagePlayback()
            self?.applyStageDebugPresentation()
        }

        interactor.onSourceClipChange = { [weak self] _ in
            self?.rebuildPreparedStagePlayback()
            self?.applyStageDebugPresentation()
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

            playbackCaptureMode = captureMode
            rebuildPreparedStagePlayback()
            prepareStagePlayback()
            navigate(to: .stage, transition: .fromLeading)
        }
    }

    func rebuildPreparedStagePlayback() {
        preparedStagePlayback = stagePlaybackBuilder.prepare(
            sourceClip: interactor.sourceClip,
            playbackClip: interactor.currentClip,
            captureMode: activePlaybackCaptureMode,
            playbackArtifacts: storedPlaybackArtifacts
        )
    }

    // MARK: - Defaults

    static func defaultCaptureMode(from modes: [CaptureMode]) -> CaptureMode {
        modes.first ?? .mock
    }

    static func normalizedRecordingContext(_ context: MotionRecordingContext) -> MotionRecordingContext {
        context.normalizedForFixedCaptureLength()
    }

    static func makeCapturedClipPreparer(for captureMode: CaptureMode) -> any CapturedClipPreparing {
        StudioPlaybackCapturedClipPreparer(captureMode: captureMode)
    }
}
