//
//  StageViewModel.swift
//  Odoro
//

import Combine
import Foundation

@MainActor
final class StageViewModel: ObservableObject {
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

    var selectedAvatarTitle: String {
        studio.selectedAvatarOption.titleText
    }

    var isPlaying: Bool {
        studio.state.isPlaying
    }

    var hasClip: Bool {
        studio.state.hasClip
    }

    var isPreparingPlayback: Bool {
        studio.isPreparingPlayback
    }

    var selectedDebugMotionViewMode: StageDebugMotionViewMode {
        studio.stageDebugMotionViewMode
    }

    var availableDebugMotionViewModes: [StageDebugMotionViewMode] {
        studio.availableStageDebugMotionViewModes
    }

    func goBack() {
        studio.goBack()
    }

    func prepareStagePlayback() {
        studio.prepareStagePlayback()
    }

    func pausePlayback() {
        studio.pausePlayback()
    }

    func openModelSelection() {
        studio.openModelSelection()
    }

    func togglePlayback() {
        studio.togglePlayback()
    }

    func saveCurrentClipToArchive() {
        studio.saveCurrentClipToArchive()
    }

    func returnToCapture() {
        studio.returnToCapture()
    }

    func setDebugMotionViewMode(_ mode: StageDebugMotionViewMode) {
        studio.setStageDebugMotionViewMode(mode)
    }

    private var currentTake: MotionTakeSummary? {
        guard let currentTakeID = studio.currentTakeID else {
            return studio.currentSessionTakes.first
        }

        return studio.currentSessionTakes.first { $0.id == currentTakeID } ?? studio.currentSessionTakes.first
    }

    private var recordingSessionSummaryText: String {
        StudioSelectionOptions.sessionSummaryText(for: studio.recordingContext)
    }
}
