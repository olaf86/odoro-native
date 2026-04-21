//
//  StudioViewModel+RecordingAudio.swift
//  Odoro
//

import Foundation

extension StudioViewModel {
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
