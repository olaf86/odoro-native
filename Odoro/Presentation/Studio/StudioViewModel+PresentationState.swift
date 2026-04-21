//
//  StudioViewModel+PresentationState.swift
//  Odoro
//

import Foundation

extension StudioViewModel {
    var isRecording: Bool { state.isRecording }
    var isPlaying: Bool { state.isPlaying }
    var hasClip: Bool { state.hasClip }
    var availableCaptureModes: [CaptureMode] { supportedCaptureModes }
    var hasLibraryClips: Bool { !libraryClips.isEmpty }
    var isCurrentTakeAccepted: Bool { currentTake?.isAccepted == true }
    var canConfirmCurrentTake: Bool { archiveStore != nil && hasClip && !isCurrentTakeAccepted }
    var canImportVideo: Bool { archiveStore != nil && !state.isRecording && !isImportingVideo }

    var currentTake: MotionTakeSummary? {
        guard let currentTakeID else {
            return currentSessionTakes.first
        }

        return currentSessionTakes.first { $0.id == currentTakeID } ?? currentSessionTakes.first
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

    var audioSourceTitle: String {
        activeAudioSource.title
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
}
