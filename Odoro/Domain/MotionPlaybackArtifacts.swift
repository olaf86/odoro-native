//
//  MotionPlaybackArtifacts.swift
//  Odoro
//

import Foundation
import simd

struct StagePlaybackCameraPreset: Codable, Sendable, Equatable {
    let lookAt: MotionPayloadVector3
    let position: MotionPayloadVector3

    nonisolated init(lookAt: SIMD3<Float>, position: SIMD3<Float>) {
        self.lookAt = MotionPayloadVector3(lookAt)
        self.position = MotionPayloadVector3(position)
    }

    nonisolated var lookAtSIMD: SIMD3<Float> {
        lookAt.simdValue
    }

    nonisolated var positionSIMD: SIMD3<Float> {
        position.simdValue
    }
}

struct StagePlaybackClipArtifacts: Codable, Sendable, Equatable {
    let appendagePoses: MotionClipAppendagePoses?
    let cameraPreset: StagePlaybackCameraPreset?

    nonisolated init(
        appendagePoses: MotionClipAppendagePoses?,
        cameraPreset: StagePlaybackCameraPreset?
    ) {
        self.appendagePoses = appendagePoses
        self.cameraPreset = cameraPreset
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
    nonisolated static let currentSchemaVersion = 2

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
                appendagePoses: preparedPlayback.raw.appendagePoses,
                cameraPreset: preparedPlayback.raw.cameraPreset
            ),
            canonical: StagePlaybackClipArtifacts(
                appendagePoses: preparedPlayback.canonical.appendagePoses,
                cameraPreset: preparedPlayback.canonical.cameraPreset
            ),
            stabilized: StagePlaybackClipArtifacts(
                appendagePoses: preparedPlayback.stabilized.appendagePoses,
                cameraPreset: preparedPlayback.stabilized.cameraPreset
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

        if case .some = clip.cameraPreset {
            return true
        }

        return false
    }
}
