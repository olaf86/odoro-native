//
//  StudioViewModel.swift
//  Odoro
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

@MainActor
final class StudioViewModel: ObservableObject {
    @Published private(set) var state = MotionStudioState()
    @Published private(set) var captureMode: CaptureMode
    @Published private(set) var recordingContext: MotionRecordingContext
    @Published private(set) var currentSessionTakes: [MotionTakeSummary] = []
    @Published private(set) var currentTakeID: UUID?

    var presentation: StudioPresentation { state.presentation }
    var statusText: String { state.statusText }
    var isRecording: Bool { state.isRecording }
    var isPlaying: Bool { state.isPlaying }
    var recordedFrameCount: Int { state.recordedFrameCount }
    var hasClip: Bool { state.hasClip }
    var availableCaptureModes: [CaptureMode] { supportedCaptureModes }
    var availableTimeSignatures: [TimeSignatureOption] { Self.supportedTimeSignatures }
    var hasSavedTakes: Bool { !currentSessionTakes.isEmpty }
    var hasCurrentTake: Bool { currentTake != nil }
    var isCurrentTakeAccepted: Bool { currentTake?.isAccepted == true }
    var canConfirmCurrentTake: Bool { archiveStore != nil && hasClip && !isCurrentTakeAccepted }

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
        return L10n.recordingSessionSummary(
            bpm,
            recordingContext.timeSignatureNumerator,
            recordingContext.timeSignatureDenominator,
            recordingContext.targetBarCount
        )
    }

    var recordingDurationText: String {
        L10n.recordingDuration(state.recordingDuration.formatted(.number.precision(.fractionLength(1))))
    }

    var clipDurationText: String {
        L10n.clipDuration(state.clipDuration.formatted(.number.precision(.fractionLength(1))))
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
    private let archiveStore: MotionArchiveStore?
    private var source: MotionSource
    private var interactor: MotionStudioInteractor
    private let stageRenderer = StagePlaybackRenderer()
    private weak var attachedCaptureARView: ARView?
    private weak var attachedFrontPreviewView: UIView?
    private var currentSessionID: UUID?

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
        interactor.activateSource()
    }

    func beginRecording() {
        interactor.activateSource()
        interactor.beginRecording()
    }

    func stopRecording() {
        interactor.stopRecording()
        persistCurrentClipIfPossible()
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
        interactor.activateSource()
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
        interactor.activateSource()
    }

    func attachCaptureView(_ view: ARView) {
        attachedCaptureARView = view
        (source as? ARKitMotionSource)?.attach(to: view)
        interactor.activateSource()
    }

    func attachFrontCaptureView(_ view: UIView) {
        attachedFrontPreviewView = view
        (source as? VisionFrontCameraMotionSource)?.attachPreview(to: view)
        interactor.activateSource()
    }

    func updateFrontCapturePreview(in view: UIView) {
        (source as? VisionFrontCameraMotionSource)?.updatePreviewFrame(to: view.bounds)
    }

    func attachStageView(_ view: ARView) {
        stageRenderer.attach(to: view)
        stageRenderer.setClip(interactor.currentClip)
    }

    func resumeCaptureSource() {
        attachCurrentSourceIfPossible()
        interactor.activateSource()
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
            prepareStagePlayback()
        } catch {
            print("Failed to load motion take: \(error)")
        }
    }

    func confirmCurrentTake() {
        do {
            let takeToConfirm = try ensureCurrentTakeForConfirmation()
            try archiveStore?.acceptTake(withID: takeToConfirm.id, inSessionID: takeToConfirm.sessionID)
            try refreshCurrentSessionTakes()
        } catch {
            print("Failed to confirm motion take: \(error)")
        }
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
}

private enum ConfirmationError: Error {
    case missingClip
    case missingTakeAfterSave
}
