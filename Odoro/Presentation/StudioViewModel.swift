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
    @Published private(set) var selectedAvatarStyle: StageAvatarStyle = .robot
    @Published private(set) var transientMessage: String?

    var presentation: StudioPresentation { state.presentation }
    var statusText: String { state.statusText }
    var isRecording: Bool { state.isRecording }
    var isPlaying: Bool { state.isPlaying }
    var recordedFrameCount: Int { state.recordedFrameCount }
    var hasClip: Bool { state.hasClip }
    var availableCaptureModes: [CaptureMode] { supportedCaptureModes }
    var availableTimeSignatures: [TimeSignatureOption] { Self.supportedTimeSignatures }
    var availableAudioSources: [AudioSourceOption] { Self.audioSources }
    var availableAvatarStyles: [StageAvatarStyle] { StageAvatarStyle.allCases }
    var hasSavedTakes: Bool { !currentSessionTakes.isEmpty }
    var hasCurrentTake: Bool { currentTake != nil }
    var hasLibraryClips: Bool { !libraryClips.isEmpty }
    var isCurrentTakeAccepted: Bool { currentTake?.isAccepted == true }
    var canConfirmCurrentTake: Bool { archiveStore != nil && hasClip && !isCurrentTakeAccepted }
    var activeAudioSource: AudioSourceOption {
        Self.audioSources.first(where: { $0.matches(recordingContext) }) ?? Self.audioSources[0]
    }

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
        recordingContext: MotionRecordingContext? = nil
    ) {
        let modes = Self.makeSupportedCaptureModes()
        let initialMode = Self.defaultCaptureMode(from: modes)
        let source = Self.makeMotionSource(for: initialMode)

        self.supportedCaptureModes = modes
        self.archiveStore = archiveStore
        self.recordingContext = recordingContext ?? .defaultMetronomeLoop
        self.captureMode = initialMode
        self.source = source
        self.interactor = MotionStudioInteractor(source: source)

        configureForCurrentSource()
        refreshLibrary()
    }

    func beginRecording() {
        guard screen == .capture else {
            navigate(to: .capture, transition: .fromLeading)
            return
        }

        dismissSwipeHints()
        attachCurrentSourceIfPossible()
        interactor.activateSource()
        interactor.beginRecording()
    }

    func stopRecording() {
        interactor.stopRecording()
    }

    func enterStageMode() {
        interactor.enterStageMode()
    }

    func returnToCapture() {
        stageRenderer.pause()
        interactor.setPlaybackActive(false)
        interactor.returnToCapture()
        navigate(to: .capture, transition: .fromLeading)
    }

    func goBack() {
        switch screen {
        case .capture:
            break
        case .musicSelection:
            navigate(to: .capture, transition: .fromLeading)
        case .sessionSettings:
            navigate(to: .capture, transition: .fromTop)
        case .clipsLibrary:
            navigate(to: .capture, transition: .fromTrailing)
        case .stage:
            returnToCapture()
        case .modelSelection:
            navigate(to: .stage, transition: .fromTop)
        case .archive:
            navigate(to: .stage, transition: .fromLeading)
        }
    }

    func openMusicSelection() {
        guard !state.isRecording else { return }
        dismissSwipeHints()
        navigate(to: .musicSelection, transition: .fromTrailing)
    }

    func openSessionSettings() {
        guard !state.isRecording else { return }
        dismissSwipeHints()
        navigate(to: .sessionSettings, transition: .fromBottom)
    }

    func openClipLibrary() {
        guard !state.isRecording else { return }
        dismissSwipeHints()
        refreshLibrary()
        navigate(to: .clipsLibrary, transition: .fromLeading)
    }

    func openModelSelection() {
        guard hasClip else { return }
        navigate(to: .modelSelection, transition: .fromBottom)
    }

    func saveCurrentClipToArchive() {
        guard hasClip else { return }
        confirmCurrentTake()
        refreshLibrary()
        navigate(to: .archive, transition: .fromTrailing)
    }

    func resetClip() {
        stageRenderer.pause()
        interactor.setPlaybackActive(false)
        stageRenderer.setClip(nil)
        interactor.resetClip()
        currentTakeID = nil
    }

    func prepareStagePlayback() {
        interactor.deactivateSource()
        stageRenderer.setAvatarStyle(selectedAvatarStyle)
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
        interactor.deactivateSource()

        captureMode = mode
        source = Self.makeMotionSource(for: mode)
        interactor = MotionStudioInteractor(source: source)
        state = MotionStudioState(statusText: mode.descriptionText)
        currentSessionID = nil
        currentTakeID = nil
        currentSessionTakes = []

        configureForCurrentSource()
        attachCurrentSourceIfPossible()
        navigate(to: .capture, transition: .fromLeading)
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
        stageRenderer.setAvatarStyle(selectedAvatarStyle)
        stageRenderer.setClip(interactor.currentClip)
    }

    func prepareCapturePreviewIfNeeded() {
        attachCurrentSourceIfPossible()
    }

    func suspendStudioForInactivity() {
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
            $0.targetBarCount = value
        }
    }

    func updateCountInBarCount(_ value: Int) {
        updateRecordingContext {
            $0.countInBarCount = value
        }
    }

    func selectAudioSource(_ option: AudioSourceOption) {
        updateRecordingContext {
            $0.tempoSourceType = option.tempoSourceType
            $0.audioAssetReference = option.audioAssetReference
            if let preferredBPM = option.preferredBPM {
                $0.bpm = preferredBPM
            }
        }
    }

    func selectAvatarStyle(_ style: StageAvatarStyle) {
        guard selectedAvatarStyle != style else { return }
        selectedAvatarStyle = style
        stageRenderer.setAvatarStyle(style)

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
                recordingContext = sessionSummary.recordingContext
            }

            let clip = try archiveStore.loadClip(fromLocalFilePath: take.localFilePath)
            currentSessionID = take.sessionID
            currentTakeID = take.id
            interactor.replaceCurrentClip(clip)
            try refreshCurrentSessionTakes()
            interactor.enterStageMode()
        } catch {
            print("Failed to load motion take: \(error)")
        }
    }

    func openTakeFromLibrary(_ take: MotionTakeSummary) {
        loadTake(take)
        navigate(to: .stage, transition: .fromTrailing)
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
        stageRenderer.setAvatarStyle(selectedAvatarStyle)

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

        if previousState.presentation != .stage, newState.presentation == .stage {
            if previousState.isRecording {
                persistCurrentClipIfPossible()
                refreshLibrary()
            }

            prepareStagePlayback()
            navigate(to: .stage, transition: .fromTrailing)
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
        case .mock:
            MockMotionSource()
        }
    }

    private func persistCurrentClipIfPossible() {
        guard
            let archiveStore,
            let currentClip = interactor.currentClip
        else {
            return
        }

        do {
            let saveResult = try archiveStore.saveTake(
                clip: currentClip,
                captureMode: captureMode,
                recordingContext: recordingContext,
                existingSessionID: currentSessionID
            )
            currentSessionID = saveResult.sessionID
            currentTakeID = saveResult.takeID
            let savedClip = try archiveStore.loadClip(fromLocalFilePath: saveResult.localFilePath)
            interactor.replaceCurrentClip(savedClip)
            try refreshCurrentSessionTakes()
        } catch {
            print("Failed to persist motion take: \(error)")
        }
    }

    private func updateRecordingContext(_ update: (inout MotionRecordingContext) -> Void) {
        var nextContext = recordingContext
        update(&nextContext)

        guard nextContext != recordingContext else {
            return
        }

        recordingContext = nextContext
        currentSessionID = nil
        currentTakeID = nil
        currentSessionTakes = []
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
}

private enum ConfirmationError: Error {
    case missingClip
    case missingTakeAfterSave
}
