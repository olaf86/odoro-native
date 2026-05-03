//
//  MotionTakeArtifacts.swift
//  Odoro
//

import Foundation

struct MotionPlaybackClipPreparer: CapturedClipPreparing, Sendable {
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

struct MotionTakeArtifacts: Sendable {
    let playbackClip: MotionClip
    let rigClip: MotionClip?
    let hints: MotionPlaybackHints?
}

struct MotionTakeArtifactsBuilder: Sendable {
    let hintsBuilder: MotionPlaybackHintsBuilder

    nonisolated init(
        hintsBuilder: MotionPlaybackHintsBuilder = MotionPlaybackHintsBuilder()
    ) {
        self.hintsBuilder = hintsBuilder
    }

    nonisolated func buildArtifacts(
        from sourceClip: MotionClip,
        captureMode: CaptureMode
    ) -> MotionTakeArtifacts {
        let playbackClip = MotionPlaybackClipPreparer(captureMode: captureMode)
            .prepareCapturedClip(sourceClip)
        let rigClip = sourceClip.rigNormalizedForStage()

        return MotionTakeArtifacts(
            playbackClip: playbackClip,
            rigClip: rigClip,
            hints: hintsBuilder.build(
                playbackClip: playbackClip,
                captureMode: captureMode
            )
        )
    }

    nonisolated func buildStoredTake(
        from sourceClip: MotionClip,
        captureMode: CaptureMode
    ) -> StoredMotionTake {
        let derived = buildArtifacts(from: sourceClip, captureMode: captureMode)
        return StoredMotionTake(
            clip: derived.playbackClip,
            sourceClip: sourceClip,
            rigClip: derived.rigClip,
            hints: derived.hints
        )
    }
}
