//
//  MotionDerivedArtifacts.swift
//  Odoro
//

import Foundation

struct MotionDerivedPlaybackArtifactsClip: Codable, Sendable, Equatable {
    let endEffectorInference: MotionClipEndEffectorInference?

    nonisolated init(endEffectorInference: MotionClipEndEffectorInference?) {
        self.endEffectorInference = endEffectorInference
    }
}

struct MotionDerivedStagePlaybackArtifacts: Codable, Sendable, Equatable {
    let raw: MotionDerivedPlaybackArtifactsClip
    let canonical: MotionDerivedPlaybackArtifactsClip
    let stabilized: MotionDerivedPlaybackArtifactsClip

    nonisolated init(
        raw: MotionDerivedPlaybackArtifactsClip,
        canonical: MotionDerivedPlaybackArtifactsClip,
        stabilized: MotionDerivedPlaybackArtifactsClip
    ) {
        self.raw = raw
        self.canonical = canonical
        self.stabilized = stabilized
    }
}

struct MotionDerivedArtifacts: Codable, Sendable, Equatable {
    nonisolated static let currentSchemaVersion = 1

    let schemaVersion: Int
    let stagePlayback: MotionDerivedStagePlaybackArtifacts?

    nonisolated init(
        schemaVersion: Int = Self.currentSchemaVersion,
        stagePlayback: MotionDerivedStagePlaybackArtifacts?
    ) {
        self.schemaVersion = schemaVersion
        self.stagePlayback = stagePlayback
    }
}

struct StoredMotionTake: Sendable {
    let clip: MotionClip
    let derivedArtifacts: MotionDerivedArtifacts?
}

struct MotionDerivedArtifactsBuilder: Sendable {
    let stagePlaybackBuilder: StagePreparedPlaybackBuilder

    nonisolated init(
        stagePlaybackBuilder: StagePreparedPlaybackBuilder = StagePreparedPlaybackBuilder()
    ) {
        self.stagePlaybackBuilder = stagePlaybackBuilder
    }

    nonisolated func build(
        playbackClip: MotionClip,
        captureMode: CaptureMode
    ) -> MotionDerivedArtifacts? {
        let preparedPlayback = stagePlaybackBuilder.prepare(
            sourceClip: nil,
            playbackClip: playbackClip,
            captureMode: captureMode
        )

        let stagePlayback = MotionDerivedStagePlaybackArtifacts(
            raw: MotionDerivedPlaybackArtifactsClip(
                endEffectorInference: preparedPlayback.raw.endEffectorInference
            ),
            canonical: MotionDerivedPlaybackArtifactsClip(
                endEffectorInference: preparedPlayback.canonical.endEffectorInference
            ),
            stabilized: MotionDerivedPlaybackArtifactsClip(
                endEffectorInference: preparedPlayback.stabilized.endEffectorInference
            )
        )

        if !containsArtifacts(stagePlayback.raw),
           !containsArtifacts(stagePlayback.canonical),
           !containsArtifacts(stagePlayback.stabilized) {
            return nil
        }

        return MotionDerivedArtifacts(stagePlayback: stagePlayback)
    }

    nonisolated private func containsArtifacts(_ clip: MotionDerivedPlaybackArtifactsClip) -> Bool {
        if case .some = clip.endEffectorInference {
            return true
        }

        return false
    }
}
