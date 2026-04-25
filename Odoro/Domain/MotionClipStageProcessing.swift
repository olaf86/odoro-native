//
//  MotionClipStageProcessing.swift
//  Odoro
//

import Foundation
import simd

struct MotionFrameQualityAssessment: Sendable {
    let score: Float
    let validPositionMask: [Bool]
    let robustCenter: SIMD3<Float>?
}

struct MotionFrameQualityEvaluator: Sendable {
    struct Tuning: Sendable {
        let invalidStagePositionYThreshold: Float = -5
        let minimumQualityJointCount = 2
        let limitedQualityMultiplier: Float = 0.25
        let fullQualitySpanUpperBound: Float = 2.8
        let degradedQualitySpanUpperBound: Float = 4.2
        let minimumSpanScore: Float = 0.2

        nonisolated init() {}
    }

    let tuning: Tuning

    nonisolated init(tuning: Tuning = .init()) {
        self.tuning = tuning
    }

    /// Scores a frame for downstream post-processing.
    ///
    /// This stage is responsible only for measurement quality:
    /// it decides how trustworthy the frame looks, but it does not mutate it.
    nonisolated func assess(_ frame: MotionFrame) -> MotionFrameQualityAssessment {
        guard !frame.jointPositions.isEmpty else {
            return MotionFrameQualityAssessment(
                score: 0,
                validPositionMask: [],
                robustCenter: nil
            )
        }

        let validPositionMask = frame.jointPositions.map(isValidStagePosition)
        let validPositions = zip(frame.jointPositions, validPositionMask)
            .compactMap { position, isValid in
                isValid ? position : nil
            }
        let validRatio = Float(validPositions.count) / Float(frame.jointPositions.count)

        guard validPositions.count >= tuning.minimumQualityJointCount else {
            return MotionFrameQualityAssessment(
                score: validRatio * tuning.limitedQualityMultiplier,
                validPositionMask: validPositionMask,
                robustCenter: robustCenter(of: validPositions)
            )
        }

        let maxSpan = span(of: validPositions).maxComponent
        let spanScore = descendingPenalty(
            value: maxSpan,
            fullPenaltyUpperBound: tuning.fullQualitySpanUpperBound,
            degradedPenaltyUpperBound: tuning.degradedQualitySpanUpperBound,
            minimumPenalty: tuning.minimumSpanScore
        )

        return MotionFrameQualityAssessment(
            score: min(max(validRatio * spanScore, 0), 1),
            validPositionMask: validPositionMask,
            robustCenter: robustCenter(of: validPositions)
        )
    }

    /// Returns a center point that is less sensitive to outliers than a simple average.
    nonisolated func robustCenter(of positions: [SIMD3<Float>]) -> SIMD3<Float>? {
        let validPositions = positions.filter(isValidStagePosition)
        guard !validPositions.isEmpty else {
            return nil
        }

        return SIMD3<Float>(
            median(validPositions.map(\.x)),
            median(validPositions.map(\.y)),
            median(validPositions.map(\.z))
        )
    }

    /// Filters out placeholder / invalid stage positions before they influence statistics.
    nonisolated func isValidStagePosition(_ position: SIMD3<Float>) -> Bool {
        position.x.isFinite &&
            position.y.isFinite &&
            position.z.isFinite &&
            position.y > tuning.invalidStagePositionYThreshold
    }

    nonisolated func span(of positions: [SIMD3<Float>]) -> SIMD3<Float> {
        guard let first = positions.first else {
            return .zero
        }

        let bounds = positions.dropFirst().reduce((min: first, max: first)) { bounds, position in
            (
                min: SIMD3<Float>(
                    Swift.min(bounds.min.x, position.x),
                    Swift.min(bounds.min.y, position.y),
                    Swift.min(bounds.min.z, position.z)
                ),
                max: SIMD3<Float>(
                    Swift.max(bounds.max.x, position.x),
                    Swift.max(bounds.max.y, position.y),
                    Swift.max(bounds.max.z, position.z)
                )
            )
        }

        return bounds.max - bounds.min
    }

    /// Returns the median of a sorted or unsorted Float collection.
    nonisolated func median(_ values: [Float]) -> Float {
        let sorted = values.sorted()
        guard !sorted.isEmpty else {
            return 0
        }

        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) * 0.5
        }

        return sorted[middle]
    }
}

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
                let isValidPosition = assessment.validPositionMask[safe: index] ?? false
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

struct MotionClipStageNormalizer: Sendable {
    let qualityEvaluator: MotionFrameQualityEvaluator
    let stabilizer: MotionClipStageStabilizer

    nonisolated init(
        qualityEvaluator: MotionFrameQualityEvaluator = .init(),
        stabilizer: MotionClipStageStabilizer? = nil
    ) {
        self.qualityEvaluator = qualityEvaluator
        self.stabilizer = stabilizer ?? MotionClipStageStabilizer(qualityEvaluator: qualityEvaluator)
    }

    /// Normalizes a clip for stage playback by stabilizing the motion and rebasing origin/floor.
    nonisolated func normalized(clip: MotionClip) -> MotionClip {
        guard let firstFrame = clip.frames.first, !clip.frames.isEmpty else {
            return clip
        }

        let stabilizedFrames = stabilizer.stabilize(clip)
        let originFrame = stabilizedFrames.first ?? firstFrame
        let firstAverage = qualityEvaluator.robustCenter(of: originFrame.jointPositions)
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

private extension MotionFrameQualityEvaluator {
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

private extension SIMD3<Float> {
    nonisolated var maxComponent: Float {
        Swift.max(x, Swift.max(y, z))
    }
}

private extension Array {
    nonisolated subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
