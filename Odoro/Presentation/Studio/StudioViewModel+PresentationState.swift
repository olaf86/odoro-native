//
//  StudioViewModel+PresentationState.swift
//  Odoro
//

import Foundation

extension StudioViewModel {
    var presentation: StudioPresentation { state.presentation }
    var statusText: String { state.statusText }
    var isRecording: Bool { state.isRecording }
    var isPlaying: Bool { state.isPlaying }
    var recordedFrameCount: Int { state.recordedFrameCount }
    var hasClip: Bool { state.hasClip }
    var availableCaptureModes: [CaptureMode] { supportedCaptureModes }
    var hasSavedTakes: Bool { !currentSessionTakes.isEmpty }
    var hasCurrentTake: Bool { currentTake != nil }
    var hasLibraryClips: Bool { !libraryClips.isEmpty }
    var isCurrentTakeAccepted: Bool { currentTake?.isAccepted == true }
    var canConfirmCurrentTake: Bool { archiveStore != nil && hasClip && !isCurrentTakeAccepted }
    var canImportVideo: Bool { archiveStore != nil && !state.isRecording && !isImportingVideo }

    var activeAudioSource: AudioSourceOption {
        StudioSelectionOptions.audioSources.first(where: { $0.matches(recordingContext) })
            ?? StudioSelectionOptions.audioSources[0]
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
}
