//
//  MotionClipStageNormalizer.swift
//  Odoro
//

import Foundation
import simd

struct MotionClipStageNormalizer: Sendable {
    let qualityEvaluator: MotionFrameQualityEvaluator
    let stabilizer: MotionClipStageStabilizer
    let stabilizationProfile: MotionClipStageStabilizer.Profile

    nonisolated init(
        qualityEvaluator: MotionFrameQualityEvaluator = .init(),
        stabilizer: MotionClipStageStabilizer? = nil,
        stabilizationProfile: MotionClipStageStabilizer.Profile = .displaySafe
    ) {
        self.qualityEvaluator = qualityEvaluator
        self.stabilizer = stabilizer ?? MotionClipStageStabilizer(qualityEvaluator: qualityEvaluator)
        self.stabilizationProfile = stabilizationProfile
    }

    /// Normalizes a clip for stage playback by stabilizing the motion and rebasing origin/floor.
    nonisolated func normalized(clip: MotionClip) -> MotionClip {
        guard let firstFrame = clip.frames.first, !clip.frames.isEmpty else {
            return clip
        }

        let stabilizedFrames = stabilizer.stabilize(clip, profile: stabilizationProfile)
        let originFrame = stabilizedFrames.first ?? firstFrame
        let firstAverage = qualityEvaluator.playbackTrackingCenter(in: originFrame)
            ?? originFrame.jointPositions.reduce(SIMD3<Float>.zero, +) / Float(max(originFrame.jointPositions.count, 1))
        let floorHeight = stabilizer.estimatedFloorHeight(in: stabilizedFrames) ?? 0

        let origin = SIMD3<Float>(firstAverage.x, floorHeight, firstAverage.z)
        let normalizedFrames = stabilizedFrames.map { frame in
            MotionFrame(
                time: frame.time,
                jointPositions: frame.jointPositions.map { $0 - origin },
                jointRotations: frame.jointRotations
            )
        }

        return MotionClip(frames: normalizedFrames)
    }
}
