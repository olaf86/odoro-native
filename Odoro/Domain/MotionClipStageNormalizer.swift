//
//  MotionClipStageNormalizer.swift
//  Odoro

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
    /// Works for both canonical 19-joint clips and raw ARKit 91-joint clips:
    /// - Canonical: spine = head − root (named joint indices)
    /// - Raw: spine = centroid of top-decile joints − centroid of bottom-decile joints
    ///   (physical layout — top joints are head/neck, bottom joints are ankles/feet)
    ///
    /// A single correction quaternion derived from the clip-wide median is applied to both
    /// positions (pivoting around the hip/body-center) and world-space rotations, so the
    /// skeleton and the avatar rig bone orientations stay consistent.
    nonisolated func tiltCorrected(_ frames: [MotionFrame]) -> [MotionFrame] {
        guard frames.count >= 3 else { return frames }

        let isCanonical = frames.first?.jointPositions.count == OdoroSkeletonDefinition.jointCount

        // Collect normalised spine vectors across all frames.
        let spineVectors: [SIMD3<Float>] = frames.compactMap { frame in
            isCanonical ? canonicalSpineVector(from: frame) : physicalSpineVector(from: frame)
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
        let rootIndex = isCanonical ? OdoroSkeletonDefinition.index(of: .root) : nil

        return frames.map { frame in
            let pivot: SIMD3<Float>
            if let rootIndex,
               frame.jointPositions.indices.contains(rootIndex),
               qualityEvaluator.isValidStagePosition(frame.jointPositions[rootIndex]) {
                pivot = frame.jointPositions[rootIndex]
            } else {
                pivot = qualityEvaluator.robustCenter(of: frame.jointPositions) ?? .zero
            }

            let correctedPositions = frame.jointPositions.map { position -> SIMD3<Float> in
                guard qualityEvaluator.isValidStagePosition(position) else { return position }
                return correction.act(position - pivot) + pivot
            }

            // Apply the same correction to world-space joint rotations so the avatar
            // rig bone orientations match the corrected positions.
            let correctedRotations: [MotionJointRotation?]? = frame.jointRotations.map { rotations in
                rotations.map { $0.map { MotionJointRotation(correction * $0.simdValue) } }
            }

            return MotionFrame(
                time: frame.time,
                jointPositions: correctedPositions,
                jointRotations: correctedRotations
            )
        }
    }

    /// Spine vector from named canonical joints (head − root).
    nonisolated func canonicalSpineVector(from frame: MotionFrame) -> SIMD3<Float>? {
        let headIndex = OdoroSkeletonDefinition.index(of: .head)
        let rootIndex = OdoroSkeletonDefinition.index(of: .root)
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

    /// Spine vector estimated from joint layout for arbitrary-count clips (e.g. raw ARKit 91-joint).
    /// The top-decile joints by Y ≈ head/neck; the bottom-decile ≈ ankles/feet.
    nonisolated func physicalSpineVector(from frame: MotionFrame) -> SIMD3<Float>? {
        let valid = frame.jointPositions.filter(qualityEvaluator.isValidStagePosition)
        guard valid.count >= 6 else { return nil }

        let sorted = valid.sorted { $0.y < $1.y }
        let band = max(2, sorted.count / 10)
        let topCenter = sorted.suffix(band).reduce(SIMD3<Float>.zero, +) / Float(band)
        let bottomCenter = sorted.prefix(band).reduce(SIMD3<Float>.zero, +) / Float(band)

        let vec = topCenter - bottomCenter
        let len = simd_length(vec)
        guard len > 0.3 else { return nil }
        return vec / len
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
