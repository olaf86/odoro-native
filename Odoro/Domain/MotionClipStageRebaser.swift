//
//  MotionClipStageRebaser.swift
//  Odoro
//

import Foundation
import simd

/// Aligns a clip to the stage origin without applying temporal smoothing.
struct MotionClipStageRebaser: Sendable {
    let qualityEvaluator: MotionFrameQualityEvaluator
    let stabilizer: MotionClipStageStabilizer

    nonisolated init(
        qualityEvaluator: MotionFrameQualityEvaluator = .init(),
        stabilizer: MotionClipStageStabilizer? = nil
    ) {
        self.qualityEvaluator = qualityEvaluator
        self.stabilizer = stabilizer ?? MotionClipStageStabilizer(qualityEvaluator: qualityEvaluator)
    }

    nonisolated func rebased(clip: MotionClip) -> MotionClip {
        guard let firstFrame = clip.frames.first, !clip.frames.isEmpty else {
            return clip
        }

        let firstAverage = qualityEvaluator.robustCenter(of: firstFrame.jointPositions)
            ?? firstFrame.jointPositions.reduce(SIMD3<Float>.zero, +) / Float(max(firstFrame.jointPositions.count, 1))
        let floorHeight = stabilizer.estimatedFloorHeight(in: clip.frames) ?? 0
        let origin = SIMD3<Float>(firstAverage.x, floorHeight, firstAverage.z)

        let rebasedFrames = clip.frames.map { frame in
            MotionFrame(
                time: frame.time,
                jointPositions: frame.jointPositions.map { $0 - origin },
                jointRotations: frame.jointRotations
            )
        }

        return MotionClip(frames: rebasedFrames)
    }
}
