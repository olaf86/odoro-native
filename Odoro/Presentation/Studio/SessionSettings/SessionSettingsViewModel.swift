//
//  SessionSettingsViewModel.swift
//  Odoro
//

import Combine
import Foundation

@MainActor
final class SessionSettingsViewModel: ObservableObject {
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

    var recordingSessionSummaryText: String {
        let bpm = Int(studio.recordingContext.bpm.rounded())
        return "\(activeAudioSource.title) • \(bpm) BPM • \(selectedTimeSignature.title) • \(studio.recordingContext.targetBarCount) bars"
    }

    var captureMode: CaptureMode {
        studio.captureMode
    }

    var availableCaptureModes: [CaptureMode] {
        studio.availableCaptureModes
    }

    var isRecording: Bool {
        studio.isRecording
    }

    var bpm: Int {
        Int(studio.recordingContext.bpm.rounded())
    }

    var selectedTimeSignature: TimeSignatureOption {
        TimeSignatureOption(
            numerator: studio.recordingContext.timeSignatureNumerator,
            denominator: studio.recordingContext.timeSignatureDenominator
        )
    }

    var availableTimeSignatures: [TimeSignatureOption] {
        StudioSelectionOptions.timeSignatures
    }

    var fixedRecordingBarCountText: String {
        "\(MotionRecordingContext.fixedCaptureBarCount) bars"
    }

    var countInBarCount: Int {
        studio.recordingContext.countInBarCount
    }

    func goBack() {
        studio.goBack()
    }

    func selectCaptureMode(_ mode: CaptureMode) {
        studio.selectCaptureMode(mode)
    }

    func updateBPM(_ bpm: Int) {
        studio.updateRecordingContext {
            $0.bpm = Double(bpm)
        }
    }

    func selectTimeSignature(_ option: TimeSignatureOption) {
        studio.updateRecordingContext {
            $0.timeSignatureNumerator = option.numerator
            $0.timeSignatureDenominator = option.denominator
        }
    }

    func updateCountInBarCount(_ value: Int) {
        studio.updateRecordingContext {
            $0.countInBarCount = value
        }
    }

    private var activeAudioSource: AudioSourceOption {
        StudioSelectionOptions.audioSources.first(where: { $0.matches(studio.recordingContext) })
            ?? StudioSelectionOptions.audioSources[0]
    }
}
