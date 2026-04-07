//
//  MotionStudioInteractor.swift
//  Visco
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

    func startSource() {
        source.start()
    }

    func stopSource() {
        source.stop()
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
        state.statusText = "収録中です。全身が入るように動いてください"
    }

    func stopRecording() {
        guard state.isRecording else { return }
        state.isRecording = false

        guard capturedFrames.count > 1 else {
            state.statusText = "十分な動きを収録できませんでした。もう一度試してください"
            return
        }

        currentClip = MotionClip(frames: capturedFrames).normalizedForStage()
        state.statusText = "収録完了。ステージで再生できます"
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
            ? "全身が映る位置に立ってください"
            : "収録済みクリップがあります。必要なら上書きできます"
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
        state.statusText = "クリップをリセットしました。新しく収録できます"
    }

    func setPlaybackActive(_ isPlaying: Bool) {
        state.isPlaying = isPlaying
    }

    private func consume(frame: MotionFrame) {
        state.statusText = state.isRecording
            ? "収録中です。ステージ用に動きを保存しています"
            : "人物を検出しました。収録を開始できます"

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
