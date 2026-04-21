//
//  CaptureViewModel.swift
//  Odoro
//

import Combine
import Foundation

@MainActor
final class CaptureViewModel: ObservableObject {
    private let studio: StudioViewModel
    private var studioChangeSubscription: AnyCancellable?

    init(studio: StudioViewModel) {
        self.studio = studio
        studioChangeSubscription = studio.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in
                self?.objectWillChange.send()
            }
        }
    }

    var swipeHintsVisible: Bool {
        studio.swipeHintsVisible
    }

    var usesMockSource: Bool {
        studio.source.captureMode == .mock
    }

    var usesFrontCameraSource: Bool {
        studio.source.captureMode == .frontUpperBody
    }

    var isRecording: Bool {
        studio.state.isRecording
    }

    var hasClip: Bool {
        studio.state.hasClip
    }

    var currentClipTitle: String {
        studio.currentTake?.clipName ?? "Current Clip"
    }

    var captureModeTitle: String {
        studio.captureMode.title
    }

    var statusText: String {
        studio.state.statusText
    }

    var captureBeatProgressText: String {
        if isRecording {
            return "\(recordedBeatCount) / \(targetBeatCount) beats"
        }

        return "Ready for \(targetBeatCount) beats"
    }

    var captureBeatSummaryText: String {
        "\(audioSourceTitle) • \(Int(studio.recordingContext.bpm.rounded())) BPM"
    }

    var captureBeatProgress: Double {
        guard targetBeatCount > 0 else {
            return 0
        }

        return min(1, max(0, Double(recordedBeatCount) / Double(targetBeatCount)))
    }

    var audioSourceTitle: String {
        activeAudioSource.title
    }

    var recordingSessionSummaryText: String {
        let bpm = Int(studio.recordingContext.bpm.rounded())
        return "\(audioSourceTitle) • \(bpm) BPM • \(selectedTimeSignature.title) • \(studio.recordingContext.targetBarCount) bars"
    }

    func revealSwipeHints() {
        studio.revealSwipeHints()
    }

    func prepareCapturePreviewIfNeeded() {
        studio.prepareCapturePreviewIfNeeded()
    }

    func openClipLibrary() {
        studio.openClipLibrary()
    }

    func openMusicSelection() {
        studio.openMusicSelection()
    }

    func openSessionSettings() {
        studio.openSessionSettings()
    }

    func enterStageMode() {
        studio.enterStageMode()
    }

    func beginRecording() {
        studio.beginRecording()
    }

    func stopRecording() {
        studio.stopRecording()
    }

    private var activeAudioSource: AudioSourceOption {
        StudioSelectionOptions.audioSources.first(where: { $0.matches(studio.recordingContext) })
            ?? StudioSelectionOptions.audioSources[0]
    }

    private var selectedTimeSignature: TimeSignatureOption {
        TimeSignatureOption(
            numerator: studio.recordingContext.timeSignatureNumerator,
            denominator: studio.recordingContext.timeSignatureDenominator
        )
    }

    private var targetBeatCount: Int {
        studio.recordingContext.targetBarCount * studio.recordingContext.timeSignatureNumerator
    }

    private var recordedBeatCount: Int {
        let rawBeats = Int((studio.state.recordingDuration * studio.recordingContext.bpm / 60).rounded(.down))
        return min(targetBeatCount, max(0, rawBeats))
    }
}
