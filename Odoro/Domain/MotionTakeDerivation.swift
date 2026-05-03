//
//  MotionTakeDerivation.swift
//  Odoro
//

import Foundation

struct MotionPlaybackClipDeriver: CapturedClipPreparing, Sendable {
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

struct MotionTakeDerivedArtifacts: Sendable {
    let playbackClip: MotionClip
    let rigClip: MotionClip?
    let hints: MotionPlaybackHints?
}

struct MotionTakeDerivationBuilder: Sendable {
    let hintsBuilder: MotionPlaybackHintsBuilder

    nonisolated init(
        hintsBuilder: MotionPlaybackHintsBuilder = MotionPlaybackHintsBuilder()
    ) {
        self.hintsBuilder = hintsBuilder
    }

    nonisolated func deriveArtifacts(
        from sourceClip: MotionClip,
        captureMode: CaptureMode
    ) -> MotionTakeDerivedArtifacts {
        let playbackClip = MotionPlaybackClipDeriver(captureMode: captureMode)
            .prepareCapturedClip(sourceClip)
        let rigClip = sourceClip.rigNormalizedForStage()

        return MotionTakeDerivedArtifacts(
            playbackClip: playbackClip,
            rigClip: rigClip,
            hints: hintsBuilder.build(
                playbackClip: playbackClip,
                captureMode: captureMode
            )
        )
    }

    nonisolated func resolveStoredTake(
        cachedPlaybackClip: MotionClip,
        sourceClip: MotionClip?,
        cachedRigClip: MotionClip?,
        cachedHints: MotionPlaybackHints?,
        captureMode: CaptureMode
    ) -> StoredMotionTake {
        guard let sourceClip else {
            return StoredMotionTake(
                clip: cachedPlaybackClip,
                sourceClip: nil,
                rigClip: cachedRigClip,
                hints: cachedHints ?? hintsBuilder.build(
                    playbackClip: cachedPlaybackClip,
                    captureMode: captureMode
                )
            )
        }

        let derived = deriveArtifacts(from: sourceClip, captureMode: captureMode)
        return StoredMotionTake(
            clip: derived.playbackClip,
            sourceClip: sourceClip,
            rigClip: derived.rigClip,
            hints: derived.hints
        )
    }
}
