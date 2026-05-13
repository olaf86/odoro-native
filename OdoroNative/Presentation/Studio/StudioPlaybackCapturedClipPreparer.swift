//
//  StudioPlaybackCapturedClipPreparer.swift
//  Odoro
//

import Foundation

struct StudioPlaybackCapturedClipPreparer: CapturedClipPreparing {
    let captureMode: CaptureMode

    nonisolated func prepareCapturedClip(_ clip: MotionClip) -> MotionClip {
        MotionPlaybackClipPreparer(captureMode: captureMode).prepareCapturedClip(clip)
    }
}
