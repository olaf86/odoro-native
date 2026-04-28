//
//  MotionPlaybackArtifacts.swift
//  Odoro
//

import Foundation

struct StagePlaybackClipArtifacts: Codable, Sendable, Equatable {
    let appendagePoses: MotionClipAppendagePoses?

    nonisolated init(appendagePoses: MotionClipAppendagePoses?) {
        self.appendagePoses = appendagePoses
    }
}

struct StagePlaybackArtifacts: Codable, Sendable, Equatable {
    let raw: StagePlaybackClipArtifacts
    let canonical: StagePlaybackClipArtifacts
    let stabilized: StagePlaybackClipArtifacts

    nonisolated init(
        raw: StagePlaybackClipArtifacts,
        canonical: StagePlaybackClipArtifacts,
        stabilized: StagePlaybackClipArtifacts
    ) {
        self.raw = raw
        self.canonical = canonical
        self.stabilized = stabilized
    }
}

struct MotionPlaybackArtifacts: Codable, Sendable, Equatable {
    nonisolated static let currentSchemaVersion = 1

    let schemaVersion: Int
    let stagePlayback: StagePlaybackArtifacts?

    nonisolated init(
        schemaVersion: Int = Self.currentSchemaVersion,
        stagePlayback: StagePlaybackArtifacts?
    ) {
        self.schemaVersion = schemaVersion
        self.stagePlayback = stagePlayback
    }
}

struct StoredMotionTake: Sendable {
    let clip: MotionClip
    let playbackArtifacts: MotionPlaybackArtifacts?
}

struct MotionPlaybackArtifactsBuilder: Sendable {
    let stagePlaybackBuilder: StagePreparedPlaybackBuilder

    nonisolated init(
        stagePlaybackBuilder: StagePreparedPlaybackBuilder = StagePreparedPlaybackBuilder()
    ) {
        self.stagePlaybackBuilder = stagePlaybackBuilder
    }

    nonisolated func build(
        playbackClip: MotionClip,
        captureMode: CaptureMode
    ) -> MotionPlaybackArtifacts? {
        let preparedPlayback = stagePlaybackBuilder.prepare(
            sourceClip: nil,
            playbackClip: playbackClip,
            captureMode: captureMode
        )

        let stagePlayback = StagePlaybackArtifacts(
            raw: StagePlaybackClipArtifacts(
                appendagePoses: preparedPlayback.raw.appendagePoses
            ),
            canonical: StagePlaybackClipArtifacts(
                appendagePoses: preparedPlayback.canonical.appendagePoses
            ),
            stabilized: StagePlaybackClipArtifacts(
                appendagePoses: preparedPlayback.stabilized.appendagePoses
            )
        )

        if !containsArtifacts(stagePlayback.raw),
           !containsArtifacts(stagePlayback.canonical),
           !containsArtifacts(stagePlayback.stabilized) {
            return nil
        }

        return MotionPlaybackArtifacts(stagePlayback: stagePlayback)
    }

    nonisolated private func containsArtifacts(_ clip: StagePlaybackClipArtifacts) -> Bool {
        if case .some = clip.appendagePoses {
            return true
        }

        return false
    }
}
