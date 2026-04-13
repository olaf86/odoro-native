//
//  MotionStudioInteractor.swift
//  Odoro
//

import Foundation

@MainActor
final class MotionStudioInteractor {
    var onStateChange: ((MotionStudioState) -> Void)?
    var onClipChange: ((MotionClip?) -> Void)?

    private(set) var state = MotionStudioState() {
        didSet {
            onStateChange?(state)
        }
    }

    private(set) var currentClip: MotionClip? {
        didSet {
            state.hasClip = currentClip != nil
            state.clipDuration = currentClip?.duration ?? 0
            onClipChange?(currentClip)
        }
    }

    private let source: MotionSource
    private let maximumCaptureDuration: TimeInterval
    private var capturedFrames: [MotionFrame] = []
    private var recordingStartTimestamp: TimeInterval?

    init(source: MotionSource, maximumCaptureDuration: TimeInterval = 10) {
        self.source = source
        self.maximumCaptureDuration = maximumCaptureDuration

        source.onFrame = { [weak self] frame in
            Task { @MainActor in
                self?.consume(frame: frame)
            }
        }

        source.onStatusTextChange = { [weak self] statusText in
            Task { @MainActor in
                self?.state.statusText = statusText
            }
        }
    }

    func activateSource() {
        source.activate()
    }

    func deactivateSource() {
        source.deactivate()
    }

    func beginRecording() {
        if state.presentation != .capture {
            returnToCapture()
        }

        capturedFrames.removeAll()
        recordingStartTimestamp = nil
        state.isRecording = true
        state.recordedFrameCount = 0
        state.recordingDuration = 0
        state.statusText = L10n.statusRecordingMoveFullBody
    }

    func stopRecording() {
        guard state.isRecording else { return }
        state.isRecording = false

        guard capturedFrames.count > 1 else {
            state.statusText = L10n.statusInsufficientMotion
            return
        }

        currentClip = MotionClip(frames: capturedFrames).normalizedForStage()
        state.statusText = L10n.statusCaptureComplete
        state.presentation = .stage
    }

    func enterStageMode() {
        guard currentClip != nil else { return }
        state.presentation = .stage
    }

    func returnToCapture() {
        state.presentation = .capture
        state.isPlaying = false
        state.statusText = currentClip == nil
            ? L10n.statusStandInFrame
            : L10n.statusClipExists
    }

    func resetClip() {
        capturedFrames.removeAll()
        recordingStartTimestamp = nil
        currentClip = nil
        state.presentation = .capture
        state.isRecording = false
        state.isPlaying = false
        state.recordedFrameCount = 0
        state.recordingDuration = 0
        state.statusText = L10n.statusClipReset
    }

    func setPlaybackActive(_ isPlaying: Bool) {
        state.isPlaying = isPlaying
    }

    private func consume(frame: MotionFrame) {
        state.statusText = state.isRecording
            ? L10n.statusRecordingSaving
            : L10n.statusBodyDetected

        guard state.isRecording else {
            return
        }

        if recordingStartTimestamp == nil {
            recordingStartTimestamp = frame.time
        }

        let relativeTime = frame.time - (recordingStartTimestamp ?? frame.time)
        let capturedFrame = MotionFrame(time: relativeTime, jointPositions: frame.jointPositions)
        capturedFrames.append(capturedFrame)
        state.recordedFrameCount = capturedFrames.count
        state.recordingDuration = relativeTime

        if relativeTime >= maximumCaptureDuration {
            stopRecording()
        }
    }
}
