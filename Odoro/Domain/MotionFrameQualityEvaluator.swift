//
//  MotionFrameQualityEvaluator.swift
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

        let span = span(of: validPositions)
        let maxSpan = Swift.max(span.x, Swift.max(span.y, span.z))
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
