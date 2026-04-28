//
//  StagePreparedPlayback.swift
//  Odoro
//

import Foundation

struct PreparedStagePlaybackClip: Sendable {
    let clip: MotionClip?
    let endEffectorInference: MotionClipEndEffectorInference?
}

struct StagePreparedPlayback: Sendable {
    let raw: PreparedStagePlaybackClip
    let canonical: PreparedStagePlaybackClip
    let stabilized: PreparedStagePlaybackClip
}

struct StagePreparedPlaybackBuilder: Sendable {
    let endEffectorInferencePass: RearBody3DEndEffectorInferencePass

    nonisolated init(
        endEffectorInferencePass: RearBody3DEndEffectorInferencePass = RearBody3DEndEffectorInferencePass()
    ) {
        self.endEffectorInferencePass = endEffectorInferencePass
    }

    nonisolated func prepare(
        sourceClip: MotionClip?,
        playbackClip: MotionClip?,
        captureMode: CaptureMode,
        storedArtifacts: MotionDerivedArtifacts? = nil
    ) -> StagePreparedPlayback {
        let rawClip = (sourceClip ?? playbackClip)?.rebasedForStage()
        let canonicalClip = canonicalPlaybackClip(sourceClip: sourceClip, playbackClip: playbackClip)
        let stabilizedClip = playbackClip

        return StagePreparedPlayback(
            raw: PreparedStagePlaybackClip(clip: rawClip, endEffectorInference: nil),
            canonical: PreparedStagePlaybackClip(
                clip: canonicalClip,
                endEffectorInference: inferredArtifacts(
                    for: canonicalClip,
                    captureMode: captureMode,
                    sourceClip: sourceClip,
                    storedInference: storedArtifacts?.stagePlayback?.canonical.endEffectorInference
                )
            ),
            stabilized: PreparedStagePlaybackClip(
                clip: stabilizedClip,
                endEffectorInference: inferredArtifacts(
                    for: stabilizedClip,
                    captureMode: captureMode,
                    sourceClip: sourceClip,
                    storedInference: storedArtifacts?.stagePlayback?.stabilized.endEffectorInference
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

    nonisolated private func inferredArtifacts(
        for clip: MotionClip?,
        captureMode: CaptureMode,
        sourceClip: MotionClip?,
        storedInference: MotionClipEndEffectorInference?
    ) -> MotionClipEndEffectorInference? {
        guard
            captureMode == .rearBody3D,
            let clip
        else {
            return nil
        }

        if sourceClip == nil,
           let storedInference,
           storedInference.frames.count == clip.frames.count {
            return storedInference
        }

        guard clip.frames.first?.jointPositions.count == OdoroSkeletonDefinition.jointCount else {
            return nil
        }

        return endEffectorInferencePass.infer(clip: clip)
    }
}
