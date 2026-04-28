//
//  StagePreparedPlayback.swift
//  Odoro
//

import Foundation

struct PreparedStagePlaybackClip: Sendable {
    let clip: MotionClip?
    let appendagePoses: MotionClipAppendagePoses?
}

struct StagePreparedPlayback: Sendable {
    let raw: PreparedStagePlaybackClip
    let canonical: PreparedStagePlaybackClip
    let stabilized: PreparedStagePlaybackClip
}

struct StagePreparedPlaybackBuilder: Sendable {
    let appendagePoseEstimator: RearBody3DAppendagePoseEstimator

    nonisolated init(
        appendagePoseEstimator: RearBody3DAppendagePoseEstimator = RearBody3DAppendagePoseEstimator()
    ) {
        self.appendagePoseEstimator = appendagePoseEstimator
    }

    nonisolated func prepare(
        sourceClip: MotionClip?,
        playbackClip: MotionClip?,
        captureMode: CaptureMode,
        playbackArtifacts: MotionPlaybackArtifacts? = nil
    ) -> StagePreparedPlayback {
        let rawClip = (sourceClip ?? playbackClip)?.rebasedForStage()
        let canonicalClip = canonicalPlaybackClip(sourceClip: sourceClip, playbackClip: playbackClip)
        let stabilizedClip = playbackClip

        return StagePreparedPlayback(
            raw: PreparedStagePlaybackClip(clip: rawClip, appendagePoses: nil),
            canonical: PreparedStagePlaybackClip(
                clip: canonicalClip,
                appendagePoses: resolvedAppendagePoses(
                    for: canonicalClip,
                    captureMode: captureMode,
                    sourceClip: sourceClip,
                    storedPoses: playbackArtifacts?.stagePlayback?.canonical.appendagePoses
                )
            ),
            stabilized: PreparedStagePlaybackClip(
                clip: stabilizedClip,
                appendagePoses: resolvedAppendagePoses(
                    for: stabilizedClip,
                    captureMode: captureMode,
                    sourceClip: sourceClip,
                    storedPoses: playbackArtifacts?.stagePlayback?.stabilized.appendagePoses
                )
            )
        )
    }

    nonisolated private func canonicalPlaybackClip(
        sourceClip: MotionClip?,
        playbackClip: MotionClip?
    ) -> MotionClip? {
        if let sourceClip {
            return OdoroCanonicalPoseMapper
                .canonicalizedClip(from: sourceClip)
                .rebasedForStage()
        }

        guard let playbackClip else {
            return nil
        }

        if playbackClip.frames.first?.jointPositions.count == OdoroSkeletonDefinition.jointCount {
            return playbackClip.rebasedForStage()
        }

        return OdoroCanonicalPoseMapper
            .canonicalizedClip(from: playbackClip)
            .rebasedForStage()
    }

    nonisolated private func resolvedAppendagePoses(
        for clip: MotionClip?,
        captureMode: CaptureMode,
        sourceClip: MotionClip?,
        storedPoses: MotionClipAppendagePoses?
    ) -> MotionClipAppendagePoses? {
        guard
            captureMode == .rearBody3D,
            let clip
        else {
            return nil
        }

        if sourceClip == nil,
           let storedPoses,
           storedPoses.frames.count == clip.frames.count {
            return storedPoses
        }

        guard clip.frames.first?.jointPositions.count == OdoroSkeletonDefinition.jointCount else {
            return nil
        }

        return appendagePoseEstimator.estimatePoses(for: clip)
    }
}
