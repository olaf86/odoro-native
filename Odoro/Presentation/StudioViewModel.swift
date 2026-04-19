//
//  StudioViewModel.swift
//

import ARKit
import Combine
import Foundation
import RealityKit
import UIKit

struct TimeSignatureOption: Identifiable, Hashable {
    var numerator: Int
    var denominator: Int

    var id: String { "\(numerator)/\(denominator)" }
    var title: String { "\(numerator)/\(denominator)" }
}

struct AudioSourceOption: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let tempoSourceType: TempoSourceType
    let audioAssetReference: String?
    let preferredBPM: Double?

    func matches(_ context: MotionRecordingContext) -> Bool {
        guard context.tempoSourceType == tempoSourceType else {
            return false
        }

        return tempoSourceType == .metronome || context.audioAssetReference == audioAssetReference
    }

    var supportsPreview: Bool {
        tempoSourceType == .metronome
    }
}

@MainActor
final class StudioViewModel: ObservableObject {
    @Published private(set) var state = MotionStudioState()
    @Published private(set) var captureMode: CaptureMode
    @Published private(set) var recordingContext: MotionRecordingContext
    @Published private(set) var currentSessionTakes: [MotionTakeSummary] = []
    @Published private(set) var libraryClips: [MotionTakeSummary] = []
    @Published private(set) var currentTakeID: UUID?
    @Published private(set) var screen: StudioScreen = .capture
    @Published private(set) var screenTransition: StudioScreenTransition = .fromTrailing
    @Published private(set) var swipeHintsVisible = false
    @Published private(set) var selectedAvatarSelection: StageAvatarSelection = AvatarCatalog.defaultSelection
    @Published private(set) var transientMessage: String?
    @Published private(set) var isImportingVideo = false
    @Published private(set) var previewingAudioSourceID: String?

    var presentation: StudioPresentation { state.presentation }
    var statusText: String { state.statusText }
    var isRecording: Bool { state.isRecording }
    var isPlaying: Bool { state.isPlaying }
    var recordedFrameCount: Int { state.recordedFrameCount }
    var hasClip: Bool { state.hasClip }
    var availableCaptureModes: [CaptureMode] { supportedCaptureModes }
    var availableTimeSignatures: [TimeSignatureOption] { Self.supportedTimeSignatures }
    var availableAudioSources: [AudioSourceOption] { Self.audioSources }
    var availableAvatarOptions: [StageAvatarOption] { AvatarCatalog.stageOptions }
    var selectedAvatarOption: StageAvatarOption { AvatarCatalog.option(for: selectedAvatarSelection) }
    var hasSavedTakes: Bool { !currentSessionTakes.isEmpty }
    var hasCurrentTake: Bool { currentTake != nil }
    var hasLibraryClips: Bool { !libraryClips.isEmpty }
    var isCurrentTakeAccepted: Bool { currentTake?.isAccepted == true }
    var canConfirmCurrentTake: Bool { archiveStore != nil && hasClip && !isCurrentTakeAccepted }
    var activeAudioSource: AudioSourceOption {
        Self.audioSources.first(where: { $0.matches(recordingContext) }) ?? Self.audioSources[0]
    }
    var canImportVideo: Bool { archiveStore != nil && !state.isRecording && !isImportingVideo }

    var currentTake: MotionTakeSummary? {
        guard let currentTakeID else {
            return currentSessionTakes.first
        }

        return currentSessionTakes.first { $0.id == currentTakeID } ?? currentSessionTakes.first
    }

    var acceptedTake: MotionTakeSummary? {
        currentSessionTakes.first { $0.isAccepted }
    }

    var selectedTimeSignature: TimeSignatureOption {
        TimeSignatureOption(
            numerator: recordingContext.timeSignatureNumerator,
            denominator: recordingContext.timeSignatureDenominator
        )
    }

    var fixedRecordingBarCountText: String {
        "\(MotionRecordingContext.fixedCaptureBarCount) bars"
    }

    var recordingSessionSummaryText: String {
        let bpm = Int(recordingContext.bpm.rounded())
        return "\(audioSourceTitle) • \(bpm) BPM • \(selectedTimeSignature.title) • \(recordingContext.targetBarCount) bars"
    }

    var recordingDurationText: String {
        L10n.recordingDuration(state.recordingDuration.formatted(.number.precision(.fractionLength(1))))
    }

    var clipDurationText: String {
        L10n.clipDuration(state.clipDuration.formatted(.number.precision(.fractionLength(1))))
    }

    var captureBeatProgressText: String {
        if isRecording {
            return "\(recordedBeatCount) / \(targetBeatCount) beats"
        }

        return "Ready for \(targetBeatCount) beats"
    }

    var captureBeatSummaryText: String {
        "\(audioSourceTitle) • \(Int(recordingContext.bpm.rounded())) BPM"
    }

    var captureBeatProgress: Double {
        guard targetBeatCount > 0 else {
            return 0
        }

        return min(1, max(0, Double(recordedBeatCount) / Double(targetBeatCount)))
    }

    var targetBeatCount: Int {
        recordingContext.targetBarCount * recordingContext.timeSignatureNumerator
    }

    var recordedBeatCount: Int {
        let rawBeats = Int((state.recordingDuration * recordingContext.bpm / 60).rounded(.down))
        return min(targetBeatCount, max(0, rawBeats))
    }

    var audioSourceTitle: String {
        activeAudioSource.title
    }

    var audioSourceSubtitle: String {
        activeAudioSource.subtitle
    }

    var currentClipTitle: String {
        currentTake?.clipName ?? "Current Clip"
    }

    var currentClipSubtitle: String {
        guard let currentTake else {
            return recordingSessionSummaryText
        }

        let bpm = Int(currentTake.bpm.rounded())
        return "\(bpm) BPM • \(currentTake.timeSignatureNumerator)/\(currentTake.timeSignatureDenominator) • \(currentTake.barLength) bars"
    }

    var usesMockSource: Bool {
        source.captureMode == .mock
    }

    var usesFrontCameraSource: Bool {
        source.captureMode == .frontUpperBody
    }

    private let supportedCaptureModes: [CaptureMode]
    private static let supportedTimeSignatures = [
        TimeSignatureOption(numerator: 3, denominator: 4),
        TimeSignatureOption(numerator: 4, denominator: 4),
    ]
    private static let audioSources = [
        AudioSourceOption(
            id: "metronome",
            title: "Metronome",
            subtitle: "A clean click track for precise timing.",
            tempoSourceType: .metronome,
            audioAssetReference: nil,
            preferredBPM: nil
        ),
        AudioSourceOption(
            id: "house-loop",
            title: "House Loop",
            subtitle: "124 BPM reference loop for groove takes.",
            tempoSourceType: .audioAsset,
            audioAssetReference: "house-loop-demo",
            preferredBPM: 124
        ),
        AudioSourceOption(
            id: "hiphop-loop",
            title: "Hip-Hop Loop",
            subtitle: "96 BPM pocket for upper-body practice.",
            tempoSourceType: .audioAsset,
            audioAssetReference: "hiphop-loop-demo",
            preferredBPM: 96
        ),
        AudioSourceOption(
            id: "breaks-loop",
            title: "Breaks Loop",
            subtitle: "132 BPM for sharper accent checks.",
            tempoSourceType: .audioAsset,
            audioAssetReference: "breaks-loop-demo",
            preferredBPM: 132
        ),
    ]

    private let videoImporter = VideoMotionImporter()
    private let maximumImportedVideoDuration: TimeInterval = 10
    private let audioPlaybackController: StudioAudioPlaybackControlling
    private let archiveStore: MotionArchiveStore?
    private var source: MotionSource
    private var interactor: MotionStudioInteractor
    private let stageRenderer = StagePlaybackRenderer()
    private weak var attachedCaptureARView: ARView?
    private weak var attachedFrontPreviewView: UIView?
    private var currentSessionID: UUID?
    private var swipeHintDismissTask: Task<Void, Never>?
    private var transientMessageDismissTask: Task<Void, Never>?

    init(
        archiveStore: MotionArchiveStore? = nil,
        recordingContext: MotionRecordingContext? = nil,
        audioPlaybackController: StudioAudioPlaybackControlling? = nil
    ) {
        let modes = Self.makeSupportedCaptureModes()
        let initialMode = Self.defaultCaptureMode(from: modes)
        let source = Self.makeMotionSource(for: initialMode)
        let normalizedRecordingContext = Self.normalizedRecordingContext(recordingContext ?? .defaultMetronomeLoop)

        self.supportedCaptureModes = modes
        self.audioPlaybackController = audioPlaybackController ?? StudioAudioPlaybackController()
        self.archiveStore = archiveStore
        self.recordingContext = normalizedRecordingContext
        self.captureMode = initialMode
        self.source = source
        self.interactor = MotionStudioInteractor(
            source: source,
            maximumCaptureDuration: normalizedRecordingContext.fixedCaptureDuration
        )

        configureForCurrentSource()
        refreshLibrary()
    }

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

    func returnToCapture() {
        stageRenderer.pause()
        interactor.setPlaybackActive(false)
        interactor.returnToCapture()
        navigate(to: .capture, transition: .fromTrailing)
    }

    func goBack() {
        switch screen {
        case .capture:
            break
        case .musicSelection:
            navigate(to: .capture, transition: .fromTrailing)
        case .sessionSettings:
            navigate(to: .capture, transition: .fromBottom)
        case .clipsLibrary:
            navigate(to: .capture, transition: .fromLeading)
        case .stage:
            returnToCapture()
        case .modelSelection:
            navigate(to: .stage, transition: .fromBottom)
        case .archive:
            navigate(to: .stage, transition: .fromTrailing)
        }
    }

    func openMusicSelection() {
        guard !state.isRecording else { return }
        dismissSwipeHints()
        navigate(to: .musicSelection, transition: .fromLeading)
    }

    func openSessionSettings() {
        guard !state.isRecording else { return }
        dismissSwipeHints()
        navigate(to: .sessionSettings, transition: .fromTop)
    }

    func openClipLibrary() {
        guard !state.isRecording else { return }
        dismissSwipeHints()
        refreshLibrary()
        navigate(to: .clipsLibrary, transition: .fromTrailing)
    }

    func openModelSelection() {
        guard hasClip else { return }
        navigate(to: .modelSelection, transition: .fromTop)
    }

    func saveCurrentClipToArchive() {
        guard hasClip else { return }
        confirmCurrentTake()
        refreshLibrary()
        navigate(to: .archive, transition: .fromLeading)
    }

    func resetClip() {
        stageRenderer.pause()
        interactor.setPlaybackActive(false)
        stageRenderer.setClip(nil)
        interactor.resetClip()
        currentTakeID = nil
    }

    func prepareStagePlayback() {
        stopAudioPlayback()
        interactor.deactivateSource()
        stageRenderer.setAvatarSelection(selectedAvatarSelection)
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

        stopAudioPlayback()
        stageRenderer.pause()
        stageRenderer.setClip(nil)
        interactor.deactivateSource()

        captureMode = mode
        source = Self.makeMotionSource(for: mode)
        interactor = MotionStudioInteractor(
            source: source,
            maximumCaptureDuration: recordingContext.fixedCaptureDuration
        )
        state = MotionStudioState(statusText: mode.descriptionText)
        currentSessionID = nil
        currentTakeID = nil
        currentSessionTakes = []

        configureForCurrentSource()
        attachCurrentSourceIfPossible()
        navigate(to: .capture, transition: .fromTrailing)
    }

    func attachCaptureView(_ view: ARView) {
        attachedCaptureARView = view
        (source as? ARKitMotionSource)?.attach(to: view)
    }

    func attachFrontCaptureView(_ view: UIView) {
        attachedFrontPreviewView = view
        (source as? VisionFrontCameraMotionSource)?.attachPreview(to: view)
    }

    func updateFrontCapturePreview(in view: UIView) {
        (source as? VisionFrontCameraMotionSource)?.updatePreviewFrame(to: view.bounds)
    }

    func attachStageView(_ view: ARView) {
        stageRenderer.attach(to: view)
        stageRenderer.setAvatarSelection(selectedAvatarSelection)
        stageRenderer.setClip(interactor.currentClip)
    }

    func prepareCapturePreviewIfNeeded() {
        attachCurrentSourceIfPossible()
    }

    func suspendStudioForInactivity() {
        stopAudioPlayback()
        stageRenderer.pause()
        interactor.setPlaybackActive(false)
        interactor.suspendForAppInactivity()
    }

    func updateBPM(_ bpm: Double) {
        updateRecordingContext {
            $0.bpm = bpm
        }
    }

    func selectTimeSignature(_ option: TimeSignatureOption) {
        updateRecordingContext {
            $0.timeSignatureNumerator = option.numerator
            $0.timeSignatureDenominator = option.denominator
        }
    }

    func updateTargetBarCount(_ value: Int) {
        updateRecordingContext {
            $0.targetBarCount = MotionRecordingContext.fixedCaptureBarCount
        }
    }

    func updateCountInBarCount(_ value: Int) {
        updateRecordingContext {
            $0.countInBarCount = value
        }
    }

    func selectAudioSource(_ option: AudioSourceOption) {
        if previewingAudioSourceID != option.id {
            stopAudioPreview()
        }

        updateRecordingContext {
            $0.tempoSourceType = option.tempoSourceType
            $0.audioAssetReference = option.audioAssetReference
            if let preferredBPM = option.preferredBPM {
                $0.bpm = preferredBPM
            }
        }
    }

    func canPreviewAudioSource(_ option: AudioSourceOption) -> Bool {
        option.supportsPreview
    }

    func isPreviewingAudioSource(_ option: AudioSourceOption) -> Bool {
        previewingAudioSourceID == option.id
    }

    func toggleAudioPreview(for option: AudioSourceOption) {
        guard option.supportsPreview else {
            showFeatureNotice("Preview audio for reference tracks is coming next.")
            return
        }

        selectAudioSource(option)

        if previewingAudioSourceID == option.id {
            stopAudioPreview()
        } else {
            startAudioPreview(for: option)
        }
    }

    func selectAvatarOption(_ option: StageAvatarOption) {
        guard selectedAvatarSelection != option.selection else { return }
        selectedAvatarSelection = option.selection
        stageRenderer.setAvatarSelection(option.selection)

        if !option.isReadyForPlayback {
            showFeatureNotice("On-demand avatar downloads are next. Playback falls back to the skeleton preview until the package is installed.")
        }

        if state.isPlaying {
            prepareStagePlayback()
        } else {
            stageRenderer.setClip(interactor.currentClip)
        }
    }

    func revealSwipeHints() {
        guard !state.isRecording, screen == .capture else { return }

        swipeHintDismissTask?.cancel()
        swipeHintsVisible = true
        swipeHintDismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.dismissSwipeHints()
        }
    }

    func dismissSwipeHints() {
        swipeHintDismissTask?.cancel()
        swipeHintsVisible = false
    }

    func loadTake(_ take: MotionTakeSummary) {
        guard let archiveStore else { return }

        do {
            if let sessionSummary = try archiveStore.fetchSessionSummary(withID: take.sessionID) {
                recordingContext = Self.normalizedRecordingContext(sessionSummary.recordingContext)
                interactor.updateMaximumCaptureDuration(recordingContext.fixedCaptureDuration)
            }

            let clip = try archiveStore.loadClip(fromLocalFilePath: take.localFilePath)
            currentSessionID = take.sessionID
            currentTakeID = take.id
            stageRenderer.setUsesProceduralMockPlayback(take.captureMode == .mock)
            interactor.replaceCurrentClip(clip)
            try refreshCurrentSessionTakes()
            interactor.enterStageMode()
        } catch {
            print("Failed to load motion take: \(error)")
        }
    }

    func openTakeFromLibrary(_ take: MotionTakeSummary) {
        loadTake(take)
        navigate(to: .stage, transition: .fromLeading)
    }

    func renameClip(_ take: MotionTakeSummary, to clipName: String) {
        guard let archiveStore else { return }

        do {
            try archiveStore.renameTake(withID: take.id, clipName: clipName)
            try refreshCurrentSessionTakes()
            refreshLibrary()
        } catch {
            print("Failed to rename clip: \(error)")
        }
    }

    func showFeatureNotice(_ message: String) {
        transientMessageDismissTask?.cancel()
        transientMessage = message
        transientMessageDismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.clearFeatureNotice()
        }
    }

    func clearFeatureNotice() {
        transientMessageDismissTask?.cancel()
        transientMessage = nil
    }

    func reportVideoImportFailure(_ error: Error) {
        let message = L10n.statusVideoImportFailed(error.localizedDescription)
        interactor.setStatusText(message)
        showFeatureNotice(message)
    }

    func importVideo(from url: URL) async {
        guard
            let archiveStore,
            !state.isRecording,
            !isImportingVideo
        else {
            return
        }

        isImportingVideo = true
        stageRenderer.pause()
        interactor.setPlaybackActive(false)
        interactor.setStatusText(L10n.statusVideoImportAnalyzing)
        showFeatureNotice(L10n.statusVideoImportAnalyzing)

        let hasSecurityScopedAccess = url.startAccessingSecurityScopedResource()

        defer {
            if hasSecurityScopedAccess {
                url.stopAccessingSecurityScopedResource()
            }
            isImportingVideo = false
        }

        do {
            let clip = try await videoImporter.importClip(
                from: url,
                maximumDuration: maximumImportedVideoDuration
            )

            guard clip.frameCount > 1 else {
                let message = L10n.statusVideoImportNoMotion
                interactor.setStatusText(message)
                showFeatureNotice(message)
                return
            }

            let normalizedClip = clip.normalizedForStage()
            let saveResult = try archiveStore.saveTake(
                clip: normalizedClip,
                captureMode: .importedVideo,
                recordingContext: recordingContext,
                existingSessionID: currentSessionID
            )

            currentSessionID = saveResult.sessionID
            currentTakeID = saveResult.takeID
            let savedClip = try archiveStore.loadClip(fromLocalFilePath: saveResult.localFilePath)
            stageRenderer.setUsesProceduralMockPlayback(false)
            interactor.replaceCurrentClip(savedClip)
            try refreshCurrentSessionTakes()
            refreshLibrary()
            interactor.setStatusText(L10n.statusVideoImportComplete)
            interactor.enterStageMode()
        } catch {
            reportVideoImportFailure(error)
        }
    }

    func confirmCurrentTake() {
        do {
            let takeToConfirm = try ensureCurrentTakeForConfirmation()
            try archiveStore?.acceptTake(withID: takeToConfirm.id, inSessionID: takeToConfirm.sessionID)
            try refreshCurrentSessionTakes()
            refreshLibrary()
        } catch {
            print("Failed to confirm motion take: \(error)")
        }
    }

    private func configureForCurrentSource() {
        stageRenderer.setUsesProceduralMockPlayback(source is MockMotionSource)
        stageRenderer.setAvatarSelection(selectedAvatarSelection)

        interactor.onStateChange = { [weak self] newState in
            self?.handleInteractorStateChange(newState)
        }

        interactor.onClipChange = { [weak self] clip in
            self?.stageRenderer.setClip(clip)
        }
    }

    private func handleInteractorStateChange(_ newState: MotionStudioState) {
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

    private func attachCurrentSourceIfPossible() {
        if let arView = attachedCaptureARView {
            (source as? ARKitMotionSource)?.attach(to: arView)
        }

        if let previewView = attachedFrontPreviewView {
            (source as? VisionFrontCameraMotionSource)?.attachPreview(to: previewView)
        }
    }

    private func navigate(to screen: StudioScreen, transition: StudioScreenTransition) {
        guard self.screen != screen || screenTransition != transition else {
            return
        }

        if self.screen == .musicSelection, screen != .musicSelection {
            stopAudioPreview()
        }

        self.screen = screen
        self.screenTransition = transition
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
        case .importedVideo:
            MockMotionSource()
        case .mock:
            MockMotionSource()
        }
    }

    private static func normalizedRecordingContext(_ context: MotionRecordingContext) -> MotionRecordingContext {
        context.normalizedForFixedCaptureLength()
    }

    private func persistCurrentClipIfPossible() {
        guard
            let currentClip = interactor.currentClip
        else {
            return
        }

        do {
            try persistClip(currentClip, captureMode: captureMode)
        } catch {
            print("Failed to persist motion take: \(error)")
        }
    }

    private func persistClip(_ clip: MotionClip, captureMode: CaptureMode) throws {
        guard let archiveStore else {
            return
        }

        let saveResult = try archiveStore.saveTake(
            clip: clip,
            captureMode: captureMode,
            recordingContext: recordingContext,
            existingSessionID: currentSessionID
        )
        currentSessionID = saveResult.sessionID
        currentTakeID = saveResult.takeID
        let savedClip = try archiveStore.loadClip(fromLocalFilePath: saveResult.localFilePath)
        stageRenderer.setUsesProceduralMockPlayback(captureMode == .mock)
        interactor.replaceCurrentClip(savedClip)
        try refreshCurrentSessionTakes()
    }

    private func updateRecordingContext(_ update: (inout MotionRecordingContext) -> Void) {
        var nextContext = recordingContext
        update(&nextContext)
        nextContext = Self.normalizedRecordingContext(nextContext)

        guard nextContext != recordingContext else {
            return
        }

        recordingContext = nextContext
        interactor.updateMaximumCaptureDuration(recordingContext.fixedCaptureDuration)
        currentSessionID = nil
        currentTakeID = nil
        currentSessionTakes = []

        if previewingAudioSourceID == activeAudioSource.id {
            startAudioPreview(for: activeAudioSource)
        }
    }

    private func ensureCurrentTakeForConfirmation() throws -> MotionTakeSummary {
        if let currentTake {
            return currentTake
        }

        guard
            let archiveStore,
            let currentClip = interactor.currentClip
        else {
            throw ConfirmationError.missingClip
        }

        let saveResult = try archiveStore.saveTake(
            clip: currentClip,
            captureMode: captureMode,
            recordingContext: recordingContext,
            existingSessionID: currentSessionID
        )
        currentSessionID = saveResult.sessionID
        currentTakeID = saveResult.takeID
        try refreshCurrentSessionTakes()

        guard let persistedTake = currentTake else {
            throw ConfirmationError.missingTakeAfterSave
        }

        return persistedTake
    }

    private func refreshCurrentSessionTakes() throws {
        guard let archiveStore, let currentSessionID else {
            currentSessionTakes = []
            return
        }

        currentSessionTakes = try archiveStore.fetchTakeSummaries(inSessionID: currentSessionID)
    }

    private func refreshLibrary() {
        guard let archiveStore else {
            libraryClips = []
            return
        }

        do {
            libraryClips = try archiveStore.fetchAllTakeSummaries()
        } catch {
            print("Failed to fetch clip library: \(error)")
            libraryClips = []
        }
    }

    private func startAudioPreview(for option: AudioSourceOption) {
        guard option.supportsPreview else { return }

        audioPlaybackController.playMetronome(with: recordingContext)
        previewingAudioSourceID = option.id
    }

    private func stopAudioPreview() {
        guard previewingAudioSourceID != nil else {
            return
        }

        stopAudioPlayback()
    }

    private func startRecordingAudioIfNeeded() {
        guard activeAudioSource.tempoSourceType == .metronome else {
            return
        }

        audioPlaybackController.playMetronome(with: recordingContext)
    }

    private func stopAudioPlayback() {
        audioPlaybackController.stop()
        previewingAudioSourceID = nil
    }
}

private enum ConfirmationError: Error {
    case missingClip
    case missingTakeAfterSave
}
