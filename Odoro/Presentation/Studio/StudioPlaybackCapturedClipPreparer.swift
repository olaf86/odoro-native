//
//  StudioPlaybackCapturedClipPreparer.swift
//  Odoro
//

import Foundation

struct StudioPlaybackCapturedClipPreparer: CapturedClipPreparing {
    let captureMode: CaptureMode

    nonisolated func prepareCapturedClip(_ clip: MotionClip) -> MotionClip {
        switch captureMode {
        case .rearBody3D, .frontUpperBody, .importedVideo:
            OdoroCanonicalPoseMapper
                .canonicalizedClip(from: clip)
                .normalizedForStage()
        case .mock:
            clip.normalizedForStage()
        }
    }
}
