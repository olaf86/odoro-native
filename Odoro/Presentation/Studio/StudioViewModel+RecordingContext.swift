//
//  StudioViewModel+RecordingContext.swift
//  Odoro
//

import Foundation

extension StudioViewModel {
    var activeAudioSource: AudioSourceOption {
        StudioSelectionOptions.audioSources.first(where: { $0.matches(recordingContext) })
            ?? StudioSelectionOptions.audioSources[0]
    }

    func updateRecordingContext(_ update: (inout MotionRecordingContext) -> Void) {
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

    func startAudioPreview(for option: AudioSourceOption) {
        guard option.supportsPreview else { return }

        audioPlaybackController.playMetronome(with: recordingContext)
        previewingAudioSourceID = option.id
    }

    func stopAudioPreview() {
        guard previewingAudioSourceID != nil else {
            return
        }

        stopAudioPlayback()
    }

    func startRecordingAudioIfNeeded() {
        guard activeAudioSource.tempoSourceType == .metronome else {
            return
        }

        audioPlaybackController.playMetronome(with: recordingContext)
    }

    func stopAudioPlayback() {
        audioPlaybackController.stop()
        previewingAudioSourceID = nil
    }
}
