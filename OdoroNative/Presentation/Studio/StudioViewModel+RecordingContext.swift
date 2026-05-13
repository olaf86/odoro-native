//
//  StudioViewModel+RecordingContext.swift
//  Odoro
//

import Foundation

extension StudioViewModel {
    var activeAudioSource: AudioSourceOption {
        StudioSelectionOptions.audioSource(matching: recordingContext)
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
}
