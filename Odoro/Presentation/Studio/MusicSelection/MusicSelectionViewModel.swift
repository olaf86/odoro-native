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
        studio.availableAudioSources
    }

    var activeAudioSource: AudioSourceOption {
        studio.activeAudioSource
    }

    func goBack() {
        studio.goBack()
    }

    func canPreviewAudioSource(_ option: AudioSourceOption) -> Bool {
        studio.canPreviewAudioSource(option)
    }

    func isPreviewingAudioSource(_ option: AudioSourceOption) -> Bool {
        studio.isPreviewingAudioSource(option)
    }

    func selectAudioSource(_ option: AudioSourceOption) {
        studio.selectAudioSource(option)
    }

    func toggleAudioPreview(for option: AudioSourceOption) {
        studio.toggleAudioPreview(for: option)
    }
}
