//
//  CapturedClipPreparing.swift
//  Odoro
//

/// Prepares a recorded raw motion clip for playback and persistence.
protocol CapturedClipPreparing: Sendable {
    nonisolated func prepareCapturedClip(_ clip: MotionClip) -> MotionClip
}

struct StageNormalizedCapturedClipPreparer: CapturedClipPreparing {
    nonisolated init() {}

    nonisolated func prepareCapturedClip(_ clip: MotionClip) -> MotionClip {
        clip.normalizedForStage()
    }
}
