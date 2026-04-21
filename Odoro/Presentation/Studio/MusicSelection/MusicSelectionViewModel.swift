//
//  MusicSelectionViewModel.swift
//  Odoro
//

import Combine
import Foundation

@MainActor
final class MusicSelectionViewModel: ObservableObject {
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

    var availableAudioSources: [AudioSourceOption] {
        StudioSelectionOptions.audioSources
    }

    var activeAudioSource: AudioSourceOption {
        StudioSelectionOptions.audioSource(matching: studio.recordingContext)
    }

    func goBack() {
        studio.goBack()
    }

    func canPreviewAudioSource(_ option: AudioSourceOption) -> Bool {
        option.supportsPreview
    }

    func isPreviewingAudioSource(_ option: AudioSourceOption) -> Bool {
        studio.previewingAudioSourceID == option.id
    }

    func selectAudioSource(_ option: AudioSourceOption) {
        if studio.previewingAudioSourceID != option.id {
            studio.stopAudioPreview()
        }

        studio.updateRecordingContext {
            $0.tempoSourceType = option.tempoSourceType
            $0.audioAssetReference = option.audioAssetReference
            if let preferredBPM = option.preferredBPM {
                $0.bpm = preferredBPM
            }
        }
    }

    func toggleAudioPreview(for option: AudioSourceOption) {
        guard option.supportsPreview else {
            studio.showFeatureNotice("Preview audio for reference tracks is coming next.")
            return
        }

        selectAudioSource(option)

        if studio.previewingAudioSourceID == option.id {
            studio.stopAudioPreview()
        } else {
            studio.startAudioPreview(for: option)
        }
    }
}
