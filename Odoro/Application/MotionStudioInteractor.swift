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
            state.recordedFrameCount = currentClip?.frameCount ?? 0
            onClipChange?(currentClip)
        }
    }

    private let source: MotionSource
    private var maximumCaptureDuration: TimeInterval
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
                self?.updateStatusTextIfNeeded(statusText)
            }
        }
    }

    func activateSource() {
        source.activate()
    }

    func updateMaximumCaptureDuration(_ duration: TimeInterval) {
        maximumCaptureDuration = duration
    }

    func deactivateSource() {
        source.deactivate()
    }

    func suspendForAppInactivity() {
        source.deactivate()

        guard state.presentation == .capture else {
            return
        }

        if state.isRecording {
            capturedFrames.removeAll()
            recordingStartTimestamp = nil
            state.isRecording = false
            state.recordedFrameCount = 0
            state.recordingDuration = 0
        }

        updateStatusTextIfNeeded(currentClip == nil ? L10n.statusStandInFrame : L10n.statusClipExists)
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
        updateStatusTextIfNeeded(L10n.statusRecordingMoveFullBody)
    }

    func stopRecording() {
        guard state.isRecording else { return }
        state.isRecording = false

        guard capturedFrames.count > 1 else {
            updateStatusTextIfNeeded(L10n.statusInsufficientMotion)
            return
        }

        currentClip = MotionClip(frames: capturedFrames).normalizedForStage()
        updateStatusTextIfNeeded(L10n.statusCaptureComplete)
        state.presentation = .stage
    }

    func enterStageMode() {
        guard currentClip != nil else { return }
        state.presentation = .stage
    }

    func returnToCapture() {
        state.presentation = .capture
        state.isPlaying = false
        updateStatusTextIfNeeded(currentClip == nil ? L10n.statusStandInFrame : L10n.statusClipExists)
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
        updateStatusTextIfNeeded(L10n.statusClipReset)
    }

    func setPlaybackActive(_ isPlaying: Bool) {
        state.isPlaying = isPlaying
    }

    func setStatusText(_ statusText: String) {
        updateStatusTextIfNeeded(statusText)
    }

    func replaceCurrentClip(_ clip: MotionClip) {
        currentClip = clip
    }

    private func consume(frame: MotionFrame) {
        guard state.isRecording else {
            return
        }

        updateStatusTextIfNeeded(L10n.statusRecordingSaving)

        if recordingStartTimestamp == nil {
            recordingStartTimestamp = frame.time
        }

        let relativeTime = frame.time - (recordingStartTimestamp ?? frame.time)
        let capturedFrame = MotionFrame(
            time: relativeTime,
            jointPositions: frame.jointPositions,
            jointRotations: frame.jointRotations
        )
        capturedFrames.append(capturedFrame)
        state.recordedFrameCount = capturedFrames.count
        state.recordingDuration = relativeTime

        if relativeTime >= maximumCaptureDuration {
            stopRecording()
        }
    }

    private func updateStatusTextIfNeeded(_ statusText: String) {
        guard state.statusText != statusText else {
            return
        }

        state.statusText = statusText
    }
}
