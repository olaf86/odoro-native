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
        studio.recordingSessionSummaryText
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
        studio.selectedTimeSignature
    }

    var availableTimeSignatures: [TimeSignatureOption] {
        studio.availableTimeSignatures
    }

    var fixedRecordingBarCountText: String {
        studio.fixedRecordingBarCountText
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
        studio.updateBPM(Double(bpm))
    }

    func selectTimeSignature(_ option: TimeSignatureOption) {
        studio.selectTimeSignature(option)
    }

    func updateCountInBarCount(_ value: Int) {
        studio.updateCountInBarCount(value)
    }
}
