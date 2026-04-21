//
//  ClipLibraryViewModel.swift
//  Odoro
//

import Combine
import Foundation

@MainActor
final class ClipLibraryViewModel: ObservableObject {
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

    var canImportVideo: Bool {
        studio.archiveStore != nil && !studio.state.isRecording && !studio.isImportingVideo
    }

    var hasLibraryClips: Bool {
        !studio.libraryClips.isEmpty
    }

    var libraryClips: [MotionTakeSummary] {
        studio.libraryClips
    }

    func goBack() {
        studio.goBack()
    }

    func renameClip(_ clip: MotionTakeSummary, to clipName: String) {
        studio.renameClip(clip, to: clipName)
    }

    func openTakeFromLibrary(_ clip: MotionTakeSummary) {
        studio.openTakeFromLibrary(clip)
    }

    func importVideo(from url: URL) async {
        await studio.importVideo(from: url)
    }

    func reportVideoImportFailure(_ error: Error) {
        studio.reportVideoImportFailure(error)
    }
}
