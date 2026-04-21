//
//  ArchiveViewModel.swift
//  Odoro
//

import Combine
import Foundation

@MainActor
final class ArchiveViewModel: ObservableObject {
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

    var clipDurationText: String {
        L10n.clipDuration(studio.state.clipDuration.formatted(.number.precision(.fractionLength(1))))
    }

    var isCurrentTakeAccepted: Bool {
        currentTake?.isAccepted == true
    }

    func goBack() {
        studio.goBack()
    }

    private var currentTake: MotionTakeSummary? {
        guard let currentTakeID = studio.currentTakeID else {
            return studio.currentSessionTakes.first
        }

        return studio.currentSessionTakes.first { $0.id == currentTakeID } ?? studio.currentSessionTakes.first
    }

    private var recordingSessionSummaryText: String {
        let bpm = Int(studio.recordingContext.bpm.rounded())
        return "\(studio.activeAudioSource.title) • \(bpm) BPM • \(selectedTimeSignature.title) • \(studio.recordingContext.targetBarCount) bars"
    }

    private var selectedTimeSignature: TimeSignatureOption {
        TimeSignatureOption(
            numerator: studio.recordingContext.timeSignatureNumerator,
            denominator: studio.recordingContext.timeSignatureDenominator
        )
    }
}
