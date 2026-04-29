//
//  MotionStudioInteractor.swift
//  Odoro
//

import Foundation

@MainActor
final class MotionStudioInteractor {
    var onStateChange: ((MotionStudioState) -> Void)?
    var onClipChange: ((MotionClip?) -> Void)?
    var onSourceClipChange: ((MotionClip?) -> Void)?

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

    private(set) var sourceClip: MotionClip? {
        didSet {
            onSourceClipChange?(sourceClip)
        }
    }

    private let source: MotionSource
    private let capturedClipPreparer: any CapturedClipPreparing
    private var maximumCaptureDuration: TimeInterval
    private let currentTime: () -> TimeInterval
    private var capturedFrames: [MotionFrame] = []
    private var firstFrameTimestamp: TimeInterval?
    private var recordingClockStartedAt: TimeInterval?
    private var recordingClockTimer: Timer?
    private let recordingClockInterval: TimeInterval = 1.0 / 30.0

    init(
        source: MotionSource,
        maximumCaptureDuration: TimeInterval = 10,
        capturedClipPreparer: any CapturedClipPreparing = StageNormalizedCapturedClipPreparer(),
        currentTime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    ) {
        self.source = source
        self.maximumCaptureDuration = maximumCaptureDuration
        self.capturedClipPreparer = capturedClipPreparer
        self.currentTime = currentTime

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

    deinit {
        recordingClockTimer?.invalidate()
    }

    func activateSource(for activity: MotionSourceActivity) {
        source.activate(for: activity)
    }

    func updateMaximumCaptureDuration(_ duration: TimeInterval) {
        maximumCaptureDuration = duration
    }

    func deactivateSource() {
        source.deactivate()
    }

    func suspendForAppInactivity() {
        stopRecordingClock()
        source.deactivate()

        guard state.presentation == .capture else {
            return
        }

        if state.isRecording {
            capturedFrames.removeAll()
            firstFrameTimestamp = nil
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

        stopRecordingClock()
        capturedFrames.removeAll()
        firstFrameTimestamp = nil
        state.isRecording = true
        state.recordedFrameCount = 0
        state.recordingDuration = 0
        updateStatusTextIfNeeded(L10n.statusRecordingMoveFullBody)
        startRecordingClock()
    }

    func stopRecording() {
        guard state.isRecording else { return }
        state.isRecording = false
        stopRecordingClock()

        guard capturedFrames.count > 1 else {
            updateStatusTextIfNeeded(L10n.statusInsufficientMotion)
            return
        }

        let rawClip = MotionClip(frames: capturedFrames)
        sourceClip = rawClip
        currentClip = capturedClipPreparer.prepareCapturedClip(rawClip)
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
        stopRecordingClock()
        capturedFrames.removeAll()
        firstFrameTimestamp = nil
        sourceClip = nil
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

    func replaceCurrentClip(_ clip: MotionClip, sourceClip: MotionClip? = nil) {
        self.sourceClip = sourceClip
        currentClip = clip
    }

    func updateRecordingClock(now: TimeInterval) {
        guard state.isRecording, let recordingClockStartedAt else {
            return
        }

        let elapsed = max(0, now - recordingClockStartedAt)
        state.recordingDuration = min(maximumCaptureDuration, elapsed)

        if elapsed >= maximumCaptureDuration {
            stopRecording()
        }
    }

    private func consume(frame: MotionFrame) {
        guard state.isRecording else {
            return
        }

        updateStatusTextIfNeeded(L10n.statusRecordingSaving)

        if firstFrameTimestamp == nil {
            firstFrameTimestamp = frame.time
        }

        let relativeTime = max(0, frame.time - (firstFrameTimestamp ?? frame.time))
        let capturedFrame = MotionFrame(
            time: relativeTime,
            jointPositions: frame.jointPositions,
            jointRotations: frame.jointRotations
        )
        capturedFrames.append(capturedFrame)
        state.recordedFrameCount = capturedFrames.count
    }

    private func updateStatusTextIfNeeded(_ statusText: String) {
        guard state.statusText != statusText else {
            return
        }

        state.statusText = statusText
    }

    private func startRecordingClock() {
        recordingClockStartedAt = currentTime()
        updateRecordingClock(now: currentTime())

        guard state.isRecording else {
            return
        }

        recordingClockTimer = Timer.scheduledTimer(
            withTimeInterval: recordingClockInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.updateRecordingClock(now: self.currentTime())
            }
        }
    }

    private func stopRecordingClock() {
        recordingClockTimer?.invalidate()
        recordingClockTimer = nil
        recordingClockStartedAt = nil
    }
}
