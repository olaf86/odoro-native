//
//  MotionPlaybackArtifacts.swift
//  Odoro
//

import Foundation
import simd

struct StagePlaybackCameraPreset: Codable, Sendable, Equatable {
    let lookAt: MotionPayloadVector3
    let position: MotionPayloadVector3

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.lookAt == rhs.lookAt && lhs.position == rhs.position
    }

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

struct StagePlaybackClipHints: Codable, Sendable, Equatable {
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

struct StagePlaybackHints: Codable, Sendable, Equatable {
    let raw: StagePlaybackClipHints
    let canonical: StagePlaybackClipHints
    let stabilized: StagePlaybackClipHints

    nonisolated init(
        raw: StagePlaybackClipHints,
        canonical: StagePlaybackClipHints,
        stabilized: StagePlaybackClipHints
    ) {
        self.raw = raw
        self.canonical = canonical
        self.stabilized = stabilized
    }
}

struct MotionPlaybackHints: Codable, Sendable, Equatable {
    nonisolated static let currentSchemaVersion = 1

    let schemaVersion: Int
    let stage: StagePlaybackHints?

    nonisolated init(
        schemaVersion: Int = Self.currentSchemaVersion,
        stage: StagePlaybackHints?
    ) {
        self.schemaVersion = schemaVersion
        self.stage = stage
    }
}

struct StoredMotionTake: Sendable {
    let clip: MotionClip
    let sourceClip: MotionClip?
    let rigClip: MotionClip?
    let hints: MotionPlaybackHints?
}

struct MotionPlaybackHintsBuilder: Sendable {
    let stagePlaybackBuilder: StagePreparedPlaybackBuilder

    nonisolated init(
        stagePlaybackBuilder: StagePreparedPlaybackBuilder = StagePreparedPlaybackBuilder()
    ) {
        self.stagePlaybackBuilder = stagePlaybackBuilder
    }

    nonisolated func build(
        playbackClip: MotionClip,
        captureMode: CaptureMode
    ) -> MotionPlaybackHints? {
        let preparedPlayback = stagePlaybackBuilder.prepare(
            sourceClip: nil,
            playbackClip: playbackClip,
            captureMode: captureMode
        )

        let stageHints = StagePlaybackHints(
            raw: StagePlaybackClipHints(
                appendagePoses: preparedPlayback.raw.appendagePoses,
                cameraPreset: preparedPlayback.raw.cameraPreset
            ),
            canonical: StagePlaybackClipHints(
                appendagePoses: preparedPlayback.canonical.appendagePoses,
                cameraPreset: preparedPlayback.canonical.cameraPreset
            ),
            stabilized: StagePlaybackClipHints(
                appendagePoses: preparedPlayback.stabilized.appendagePoses,
                cameraPreset: preparedPlayback.stabilized.cameraPreset
            )
        )

        if !containsHints(stageHints.raw),
           !containsHints(stageHints.canonical),
           !containsHints(stageHints.stabilized) {
            return nil
        }

        return MotionPlaybackHints(stage: stageHints)
    }

    nonisolated private func containsHints(_ clip: StagePlaybackClipHints) -> Bool {
        if case .some = clip.appendagePoses {
            return true
        }

        if case .some = clip.cameraPreset {
            return true
        }

        return false
    }
}
