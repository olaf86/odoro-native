//
//  MotionClipStageStabilizer.swift
//  Odoro
//

import Foundation
import simd

struct MotionClipStageStabilizer: Sendable {
    struct Tuning: Sendable {
        let minimumFrameCount = 3
        let fallbackDeltaTime: TimeInterval = 1.0 / 30.0
        let centerFullSpeedUpperBound: Float = 3.5
        let centerDegradedSpeedUpperBound: Float = 7
        let centerMinimumPenalty: Float = 0.18
        let centerAlphaFloor: Float = 0.08
        let centerAlphaBase: Float = 0.12
        let centerAlphaScale: Float = 0.72
        let centerAlphaCeiling: Float = 0.92

        let localDeltaFullPenaltyUpperBound: Float = 0.35
        let localDeltaDegradedPenaltyUpperBound: Float = 1.0
        let localDeltaMinimumPenalty: Float = 0.12
        let jointAlphaFloor: Float = 0.06
        let jointAlphaBase: Float = 0.08
        let jointAlphaScale: Float = 0.76
        let jointAlphaCeiling: Float = 0.88

        let rotationDeltaFullPenaltyUpperBound: Float = 0.45
        let rotationDeltaDegradedPenaltyUpperBound: Float = 1.2
        let rotationDeltaMinimumPenalty: Float = 0.18
        let rotationAlphaFloor: Float = 0.08
        let rotationAlphaBase: Float = 0.1
        let rotationAlphaScale: Float = 0.75
        let rotationAlphaCeiling: Float = 0.9

        let floorHeightPercentile: Float = 0.05

        nonisolated init() {}
    }

    private struct State {
        var time: TimeInterval
        var center: SIMD3<Float>
        var localPositions: [SIMD3<Float>?]
        var rotations: [MotionJointRotation?]?
    }

    let qualityEvaluator: MotionFrameQualityEvaluator
    let tuning: Tuning

    nonisolated init(
        qualityEvaluator: MotionFrameQualityEvaluator = .init(),
        tuning: Tuning = .init()
    ) {
        self.qualityEvaluator = qualityEvaluator
        self.tuning = tuning
    }

    /// Applies a lightweight post-process stabilization pass to a recorded clip.
    ///
    /// This is not a Kalman filter. It consumes precomputed frame quality and
    /// uses quality-weighted temporal smoothing to reduce spikes.
    nonisolated func stabilize(_ clip: MotionClip) -> [MotionFrame] {
        guard clip.frames.count >= tuning.minimumFrameCount, let firstFrame = clip.frames.first else {
            return clip.frames
        }

        var state = State(
            time: firstFrame.time,
            center: qualityEvaluator.robustCenter(of: firstFrame.jointPositions) ?? .zero,
            localPositions: Array(repeating: nil, count: firstFrame.jointPositions.count),
            rotations: firstFrame.jointRotations
        )

        return clip.frames.map { frame in
            let assessment = qualityEvaluator.assess(frame)
            let observedCenter = assessment.robustCenter ?? state.center
            let deltaTime = max(frame.time - state.time, tuning.fallbackDeltaTime)
            let centerAlpha = centerSmoothingAlpha(
                quality: assessment.score,
                centerDelta: simd_length(observedCenter - state.center),
                deltaTime: deltaTime
            )
            state.center = mix(state.center, observedCenter, alpha: centerAlpha)

            let jointPositions = frame.jointPositions.enumerated().map { index, position in
                let isValidPosition = assessment.validPositionMask.indices.contains(index)
                    ? assessment.validPositionMask[index]
                    : false
                guard isValidPosition else {
                    return state.localPositions[safe: index]
                        .flatMap { $0 }
                        .map { state.center + $0 } ?? position
                }

                let observedLocal = position - observedCenter
                let previousLocal = state.localPositions[safe: index].flatMap { $0 }
                let jointAlpha = jointSmoothingAlpha(
                    quality: assessment.score,
                    observedLocal: observedLocal,
                    previousLocal: previousLocal
                )
                let smoothedLocal = previousLocal.map {
                    mix($0, observedLocal, alpha: jointAlpha)
                } ?? observedLocal

                if state.localPositions.indices.contains(index) {
                    state.localPositions[index] = smoothedLocal
                }

                return state.center + smoothedLocal
            }

            let jointRotations = smoothedRotations(
                observed: frame.jointRotations,
                previous: state.rotations,
                quality: assessment.score
            )
            state.rotations = jointRotations ?? state.rotations
            state.time = frame.time

            return MotionFrame(
                time: frame.time,
                jointPositions: jointPositions,
                jointRotations: jointRotations
            )
        }
    }

    /// Estimates a stable stage floor using a low percentile instead of the raw minimum.
    nonisolated func estimatedFloorHeight(in frames: [MotionFrame]) -> Float? {
        let ys = frames
            .flatMap(\.jointPositions)
            .filter(qualityEvaluator.isValidStagePosition)
            .map(\.y)
            .sorted()

        guard !ys.isEmpty else {
            return nil
        }

        return percentile(tuning.floorHeightPercentile, in: ys)
    }

    /// Computes how aggressively to follow observed body-center motion for the next frame.
    nonisolated func centerSmoothingAlpha(quality: Float, centerDelta: Float, deltaTime: TimeInterval) -> Float {
        let interval = max(Float(deltaTime), Float(tuning.fallbackDeltaTime))
        let speed = centerDelta / interval
        let speedPenalty = descendingPenalty(
            value: speed,
            fullPenaltyUpperBound: tuning.centerFullSpeedUpperBound,
            degradedPenaltyUpperBound: tuning.centerDegradedSpeedUpperBound,
            minimumPenalty: tuning.centerMinimumPenalty
        )

        return clampedAlpha(
            base: tuning.centerAlphaBase,
            quality: quality,
            penalty: speedPenalty,
            scale: tuning.centerAlphaScale,
            floor: tuning.centerAlphaFloor,
            ceiling: tuning.centerAlphaCeiling
        )
    }

    /// Computes how aggressively to follow observed joint motion in body-local space.
    nonisolated func jointSmoothingAlpha(
        quality: Float,
        observedLocal: SIMD3<Float>,
        previousLocal: SIMD3<Float>?
    ) -> Float {
        guard let previousLocal else {
            return 1
        }

        let localDelta = simd_length(observedLocal - previousLocal)
        let spikePenalty = descendingPenalty(
            value: localDelta,
            fullPenaltyUpperBound: tuning.localDeltaFullPenaltyUpperBound,
            degradedPenaltyUpperBound: tuning.localDeltaDegradedPenaltyUpperBound,
            minimumPenalty: tuning.localDeltaMinimumPenalty
        )

        return clampedAlpha(
            base: tuning.jointAlphaBase,
            quality: quality,
            penalty: spikePenalty,
            scale: tuning.jointAlphaScale,
            floor: tuning.jointAlphaFloor,
            ceiling: tuning.jointAlphaCeiling
        )
    }

    /// Spherically interpolates joint rotations to soften single-frame spikes.
    nonisolated func smoothedRotations(
        observed: [MotionJointRotation?]?,
        previous: [MotionJointRotation?]?,
        quality: Float
    ) -> [MotionJointRotation?]? {
        guard let observed else {
            return nil
        }

        guard let previous, previous.count == observed.count else {
            return observed
        }

        return observed.enumerated().map { index, rotation in
            guard
                let rotation,
                let previousRotation = previous[index]
            else {
                return rotation ?? previous[index]
            }

            let observedQuat = rotation.simdValue
            let previousQuat = previousRotation.simdValue
            let angularDelta = angleBetween(previousQuat, observedQuat)
            let spikePenalty = descendingPenalty(
                value: angularDelta,
                fullPenaltyUpperBound: tuning.rotationDeltaFullPenaltyUpperBound,
                degradedPenaltyUpperBound: tuning.rotationDeltaDegradedPenaltyUpperBound,
                minimumPenalty: tuning.rotationDeltaMinimumPenalty
            )

            let alpha = clampedAlpha(
                base: tuning.rotationAlphaBase,
                quality: quality,
                penalty: spikePenalty,
                scale: tuning.rotationAlphaScale,
                floor: tuning.rotationAlphaFloor,
                ceiling: tuning.rotationAlphaCeiling
            )
            return MotionJointRotation(simd_slerp(previousQuat, observedQuat, alpha))
        }
    }

    /// Returns the nearest-rank percentile for an already sorted array of values.
    nonisolated func percentile(_ percentile: Float, in sortedValues: [Float]) -> Float {
        guard let first = sortedValues.first, sortedValues.count > 1 else {
            return sortedValues.first ?? 0
        }

        let clampedPercentile = min(max(percentile, 0), 1)
        let index = Int((Float(sortedValues.count - 1) * clampedPercentile).rounded(.down))
        return sortedValues[safe: index] ?? first
    }

    /// Measures the angular difference between two unit quaternions.
    nonisolated func angleBetween(_ lhs: simd_quatf, _ rhs: simd_quatf) -> Float {
        let dot = abs(simd_dot(lhs.vector, rhs.vector))
        return 2 * acos(min(max(dot, -1), 1))
    }

    /// Linearly interpolates between two 3D vectors.
    nonisolated func mix(_ lhs: SIMD3<Float>, _ rhs: SIMD3<Float>, alpha: Float) -> SIMD3<Float> {
        lhs + (rhs - lhs) * alpha
    }

    /// Converts a quality/penalty pair into a bounded smoothing coefficient.
    nonisolated func clampedAlpha(
        base: Float,
        quality: Float,
        penalty: Float,
        scale: Float,
        floor: Float,
        ceiling: Float
    ) -> Float {
        min(max(base + quality * penalty * scale, floor), ceiling)
    }
}

private extension MotionClipStageStabilizer {
    /// Produces a penalty curve that stays at 1 until a threshold, then decays linearly.
    nonisolated func descendingPenalty(
        value: Float,
        fullPenaltyUpperBound: Float,
        degradedPenaltyUpperBound: Float,
        minimumPenalty: Float
    ) -> Float {
        if value <= fullPenaltyUpperBound {
            return 1
        }

        if value >= degradedPenaltyUpperBound {
            return minimumPenalty
        }

        let progress = (value - fullPenaltyUpperBound) / (degradedPenaltyUpperBound - fullPenaltyUpperBound)
        return 1 - progress * (1 - minimumPenalty)
    }
}

private extension Array {
    nonisolated subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
