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
        let tiltCorrectedFrames = tiltCorrected(stabilizedFrames)
        let originFrame = tiltCorrectedFrames.first ?? firstFrame
        let firstAverage = qualityEvaluator.playbackTrackingCenter(in: originFrame)
            ?? originFrame.jointPositions.reduce(SIMD3<Float>.zero, +) / Float(max(originFrame.jointPositions.count, 1))
        let floorHeight = stabilizer.estimatedFloorHeight(in: tiltCorrectedFrames) ?? 0

        let origin = SIMD3<Float>(firstAverage.x, floorHeight, firstAverage.z)
        let normalizedFrames = tiltCorrectedFrames.map { frame in
            MotionFrame(
                time: frame.time,
                jointPositions: frame.jointPositions.map { $0 - origin },
                jointRotations: frame.jointRotations
            )
        }

        return MotionClip(frames: normalizedFrames)
    }
}

private extension MotionClipStageNormalizer {
    /// Removes systematic world-space body tilt by analysing the spine axis across all frames.
    ///
    /// ARKit body tracking occasionally produces a clip where the whole body leans in one
    /// direction relative to the true vertical. This pass collects the spine vector
    /// (head − root) for every frame, finds the median direction, and rotates every joint
    /// around the root pivot so that median spine aligns with world Y. Intentional per-frame
    /// leaning is preserved because the correction is a single global rotation derived from
    /// the clip median, not a per-frame straightening.
    nonisolated func tiltCorrected(_ frames: [MotionFrame]) -> [MotionFrame] {
        guard frames.count >= 3,
              let firstFrame = frames.first,
              firstFrame.jointPositions.count == OdoroSkeletonDefinition.jointCount
        else {
            return frames
        }

        let headIndex = OdoroSkeletonDefinition.index(of: .head)
        let rootIndex = OdoroSkeletonDefinition.index(of: .root)

        // Collect normalised spine vectors across all frames.
        let spineVectors: [SIMD3<Float>] = frames.compactMap { frame in
            guard frame.jointPositions.indices.contains(headIndex),
                  frame.jointPositions.indices.contains(rootIndex)
            else { return nil }

            let head = frame.jointPositions[headIndex]
            let root = frame.jointPositions[rootIndex]
            guard qualityEvaluator.isValidStagePosition(head),
                  qualityEvaluator.isValidStagePosition(root)
            else { return nil }

            let vec = head - root
            let len = simd_length(vec)
            guard len > 0.1 else { return nil }
            return vec / len
        }

        guard spineVectors.count >= 3 else { return frames }

        // Component-wise median is more robust than mean against outlier frames.
        let medX = median(spineVectors.map(\.x))
        let medY = median(spineVectors.map(\.y))
        let medZ = median(spineVectors.map(\.z))
        let medSpine = SIMD3<Float>(medX, medY, medZ)
        let medSpineLen = simd_length(medSpine)
        guard medSpineLen > 0.001 else { return frames }
        let normalizedSpine = medSpine / medSpineLen

        // Skip correction when the body axis is already nearly vertical.
        let worldUp = SIMD3<Float>(0, 1, 0)
        guard simd_dot(normalizedSpine, worldUp) < 0.9998 else { return frames }

        let correction = quaternionFromTo(normalizedSpine, worldUp)

        return frames.map { frame in
            guard frame.jointPositions.count == OdoroSkeletonDefinition.jointCount,
                  frame.jointPositions.indices.contains(rootIndex)
            else { return frame }

            let pivot = frame.jointPositions[rootIndex]
            guard qualityEvaluator.isValidStagePosition(pivot) else { return frame }

            let correctedPositions = frame.jointPositions.map { position -> SIMD3<Float> in
                guard qualityEvaluator.isValidStagePosition(position) else { return position }
                return correction.act(position - pivot) + pivot
            }

            return MotionFrame(
                time: frame.time,
                jointPositions: correctedPositions,
                jointRotations: frame.jointRotations
            )
        }
    }

    /// Returns the shortest-arc quaternion that rotates unit vector `from` to unit vector `to`.
    nonisolated func quaternionFromTo(_ from: SIMD3<Float>, _ to: SIMD3<Float>) -> simd_quatf {
        let cross = simd_cross(from, to)
        let crossLen = simd_length(cross)
        let dot = simd_dot(from, to)

        if crossLen < 0.0001 {
            if dot > 0 {
                return simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
            }
            // 180-degree case: pick an arbitrary perpendicular axis.
            let perp = abs(from.x) < 0.9
                ? simd_normalize(simd_cross(from, SIMD3<Float>(1, 0, 0)))
                : simd_normalize(simd_cross(from, SIMD3<Float>(0, 0, 1)))
            return simd_quatf(angle: .pi, axis: perp)
        }

        return simd_quatf(angle: atan2(crossLen, dot), axis: cross / crossLen)
    }

    nonisolated func median(_ values: [Float]) -> Float {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        let mid = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[mid - 1] + sorted[mid]) * 0.5 : sorted[mid]
    }
}
