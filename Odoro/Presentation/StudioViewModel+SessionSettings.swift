//
//  StudioViewModel+SessionSettings.swift
//  Odoro
//

import Foundation

extension StudioViewModel {
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
