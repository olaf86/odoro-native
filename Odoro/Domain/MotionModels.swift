//
//  MotionModels.swift
//  Odoro
//

import Foundation
import simd

enum StudioPresentation: Equatable {
    case capture
    case stage
}

enum StudioScreen: String, Equatable {
    case capture
    case musicSelection
    case sessionSettings
    case clipsLibrary
    case stage
    case modelSelection
    case archive
}

enum StudioScreenTransition: Equatable {
    case fromLeading
    case fromTrailing
    case fromTop
    case fromBottom
}

struct MotionJointRotation: Codable, Sendable, Equatable, Hashable {
    let ix: Float
    let iy: Float
    let iz: Float
    let r: Float

    nonisolated init(ix: Float, iy: Float, iz: Float, r: Float) {
        self.ix = ix
        self.iy = iy
        self.iz = iz
        self.r = r
    }

    nonisolated init(_ quaternion: simd_quatf) {
        let vector = quaternion.vector
        self.init(ix: vector.x, iy: vector.y, iz: vector.z, r: vector.w)
    }

    nonisolated var simdValue: simd_quatf {
        simd_quatf(vector: SIMD4<Float>(ix, iy, iz, r))
    }
}

struct MotionFrame: Sendable {
    let time: TimeInterval
    let jointPositions: [SIMD3<Float>]
    let jointRotations: [MotionJointRotation?]?

    nonisolated init(
        time: TimeInterval,
        jointPositions: [SIMD3<Float>],
        jointRotations: [MotionJointRotation?]? = nil
    ) {
        self.time = time
        self.jointPositions = jointPositions
        self.jointRotations = jointRotations
    }
}

struct MotionClip: Sendable {
    let frames: [MotionFrame]

    var duration: TimeInterval {
        frames.last?.time ?? 0
    }

    var frameCount: Int {
        frames.count
    }

    var isEmpty: Bool {
        frames.isEmpty
    }

    var estimatedFrameRate: Double {
        guard frames.count > 1, duration > 0 else {
            return 0
        }

        return Double(frames.count - 1) / duration
    }

    nonisolated func normalizedForStage() -> MotionClip {
        guard let firstFrame = frames.first, !frames.isEmpty else {
            return self
        }

        let stabilizedFrames = stageStabilizedFrames()
        let originFrame = stabilizedFrames.first ?? firstFrame
        let firstAverage = Self.robustCenter(of: originFrame.jointPositions)
            ?? originFrame.jointPositions.reduce(SIMD3<Float>.zero, +) / Float(max(originFrame.jointPositions.count, 1))
        let floorHeight = Self.estimatedFloorHeight(in: stabilizedFrames) ?? 0

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

private struct MotionClipStageStabilizerTuning: Sendable {
    let minimumFrameCount = 3
    let fallbackDeltaTime: TimeInterval = 1.0 / 30.0
    let invalidStagePositionYThreshold: Float = -5

    let minimumQualityJointCount = 2
    let limitedQualityMultiplier: Float = 0.25
    let fullQualitySpanUpperBound: Float = 2.8
    let degradedQualitySpanUpperBound: Float = 4.2
    let minimumSpanScore: Float = 0.2

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

private extension MotionClip {
    nonisolated static var stageStabilizerTuning: MotionClipStageStabilizerTuning {
        MotionClipStageStabilizerTuning()
    }

    struct StabilizerState {
        var time: TimeInterval
        var center: SIMD3<Float>
        var localPositions: [SIMD3<Float>?]
        var rotations: [MotionJointRotation?]?
    }

    /// Applies a lightweight post-process stabilization pass to a recorded clip.
    ///
    /// This is not a Kalman filter. It uses quality-weighted temporal smoothing:
    /// 1. estimate a robust body center per frame,
    /// 2. smooth center motion over time,
    /// 3. smooth each joint in body-local space,
    /// 4. smooth joint rotations with slerp,
    /// 5. keep invalid observations from contaminating the running state.
    nonisolated func stageStabilizedFrames() -> [MotionFrame] {
        guard frames.count >= Self.stageStabilizerTuning.minimumFrameCount, let firstFrame = frames.first else {
            return frames
        }

        var state = StabilizerState(
            time: firstFrame.time,
            center: Self.robustCenter(of: firstFrame.jointPositions) ?? .zero,
            localPositions: Array(repeating: nil, count: firstFrame.jointPositions.count),
            rotations: firstFrame.jointRotations
        )

        return frames.map { frame in
            let quality = Self.qualityScore(for: frame)
            let observedCenter = Self.robustCenter(of: frame.jointPositions) ?? state.center
            let deltaTime = max(frame.time - state.time, Self.stageStabilizerTuning.fallbackDeltaTime)
            let centerAlpha = Self.centerSmoothingAlpha(
                quality: quality,
                centerDelta: simd_length(observedCenter - state.center),
                deltaTime: deltaTime
            )
            state.center = Self.mix(state.center, observedCenter, alpha: centerAlpha)

            let jointPositions = frame.jointPositions.enumerated().map { index, position in
                guard Self.isValidStagePosition(position) else {
                    return state.localPositions[safe: index].flatMap { $0 }.map { state.center + $0 } ?? position
                }

                let observedLocal = position - observedCenter
                let previousLocal = state.localPositions[safe: index].flatMap { $0 }
                let jointAlpha = Self.jointSmoothingAlpha(
                    quality: quality,
                    observedLocal: observedLocal,
                    previousLocal: previousLocal
                )
                let smoothedLocal = previousLocal.map {
                    Self.mix($0, observedLocal, alpha: jointAlpha)
                } ?? observedLocal

                if state.localPositions.indices.contains(index) {
                    state.localPositions[index] = smoothedLocal
                }

                return state.center + smoothedLocal
            }

            let jointRotations = Self.smoothedRotations(
                observed: frame.jointRotations,
                previous: state.rotations,
                quality: quality
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

    /// Returns a coarse confidence score for a frame based on valid joint count and body span.
    nonisolated static func qualityScore(for frame: MotionFrame) -> Float {
        guard !frame.jointPositions.isEmpty else {
            return 0
        }

        let validPositions = frame.jointPositions.filter(isValidStagePosition)
        let validRatio = Float(validPositions.count) / Float(frame.jointPositions.count)
        guard validPositions.count >= Self.stageStabilizerTuning.minimumQualityJointCount else {
            return validRatio * Self.stageStabilizerTuning.limitedQualityMultiplier
        }

        let span = Self.span(of: validPositions)
        let maxSpan = max(span.x, span.y, span.z)
        let spanScore = descendingPenalty(
            value: maxSpan,
            fullPenaltyUpperBound: Self.stageStabilizerTuning.fullQualitySpanUpperBound,
            degradedPenaltyUpperBound: Self.stageStabilizerTuning.degradedQualitySpanUpperBound,
            minimumPenalty: Self.stageStabilizerTuning.minimumSpanScore
        )

        return min(max(validRatio * spanScore, 0), 1)
    }

    /// Computes how aggressively to follow observed body-center motion for the next frame.
    nonisolated static func centerSmoothingAlpha(quality: Float, centerDelta: Float, deltaTime: TimeInterval) -> Float {
        let interval = max(Float(deltaTime), Float(Self.stageStabilizerTuning.fallbackDeltaTime))
        let speed = centerDelta / interval
        let speedPenalty = descendingPenalty(
            value: speed,
            fullPenaltyUpperBound: Self.stageStabilizerTuning.centerFullSpeedUpperBound,
            degradedPenaltyUpperBound: Self.stageStabilizerTuning.centerDegradedSpeedUpperBound,
            minimumPenalty: Self.stageStabilizerTuning.centerMinimumPenalty
        )

        return clampedAlpha(
            base: Self.stageStabilizerTuning.centerAlphaBase,
            quality: quality,
            penalty: speedPenalty,
            scale: Self.stageStabilizerTuning.centerAlphaScale,
            floor: Self.stageStabilizerTuning.centerAlphaFloor,
            ceiling: Self.stageStabilizerTuning.centerAlphaCeiling
        )
    }

    /// Computes how aggressively to follow observed joint motion in body-local space.
    nonisolated static func jointSmoothingAlpha(
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
            fullPenaltyUpperBound: Self.stageStabilizerTuning.localDeltaFullPenaltyUpperBound,
            degradedPenaltyUpperBound: Self.stageStabilizerTuning.localDeltaDegradedPenaltyUpperBound,
            minimumPenalty: Self.stageStabilizerTuning.localDeltaMinimumPenalty
        )

        return clampedAlpha(
            base: Self.stageStabilizerTuning.jointAlphaBase,
            quality: quality,
            penalty: spikePenalty,
            scale: Self.stageStabilizerTuning.jointAlphaScale,
            floor: Self.stageStabilizerTuning.jointAlphaFloor,
            ceiling: Self.stageStabilizerTuning.jointAlphaCeiling
        )
    }

    /// Spherically interpolates joint rotations to soften single-frame spikes.
    nonisolated static func smoothedRotations(
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
                fullPenaltyUpperBound: Self.stageStabilizerTuning.rotationDeltaFullPenaltyUpperBound,
                degradedPenaltyUpperBound: Self.stageStabilizerTuning.rotationDeltaDegradedPenaltyUpperBound,
                minimumPenalty: Self.stageStabilizerTuning.rotationDeltaMinimumPenalty
            )

            let alpha = clampedAlpha(
                base: Self.stageStabilizerTuning.rotationAlphaBase,
                quality: quality,
                penalty: spikePenalty,
                scale: Self.stageStabilizerTuning.rotationAlphaScale,
                floor: Self.stageStabilizerTuning.rotationAlphaFloor,
                ceiling: Self.stageStabilizerTuning.rotationAlphaCeiling
            )
            return MotionJointRotation(simd_slerp(previousQuat, observedQuat, alpha))
        }
    }

    /// Estimates a stable stage floor using a low percentile instead of the raw minimum.
    nonisolated static func estimatedFloorHeight(in frames: [MotionFrame]) -> Float? {
        let ys = frames
            .flatMap(\.jointPositions)
            .filter(isValidStagePosition)
            .map(\.y)
            .sorted()

        guard !ys.isEmpty else {
            return nil
        }

        return percentile(Self.stageStabilizerTuning.floorHeightPercentile, in: ys)
    }

    /// Returns a center point that is less sensitive to outliers than a simple average.
    nonisolated static func robustCenter(of positions: [SIMD3<Float>]) -> SIMD3<Float>? {
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

    nonisolated static func span(of positions: [SIMD3<Float>]) -> SIMD3<Float> {
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
    nonisolated static func median(_ values: [Float]) -> Float {
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

    /// Returns the nearest-rank percentile for an already sorted array of values.
    nonisolated static func percentile(_ percentile: Float, in sortedValues: [Float]) -> Float {
        guard let first = sortedValues.first, sortedValues.count > 1 else {
            return sortedValues.first ?? 0
        }

        let clampedPercentile = min(max(percentile, 0), 1)
        let index = Int((Float(sortedValues.count - 1) * clampedPercentile).rounded(.down))
        return sortedValues[safe: index] ?? first
    }

    /// Measures the angular difference between two unit quaternions.
    nonisolated static func angleBetween(_ lhs: simd_quatf, _ rhs: simd_quatf) -> Float {
        let dot = abs(simd_dot(lhs.vector, rhs.vector))
        return 2 * acos(min(max(dot, -1), 1))
    }

    /// Linearly interpolates between two 3D vectors.
    nonisolated static func mix(_ lhs: SIMD3<Float>, _ rhs: SIMD3<Float>, alpha: Float) -> SIMD3<Float> {
        lhs + (rhs - lhs) * alpha
    }

    /// Converts a quality/penalty pair into a bounded smoothing coefficient.
    nonisolated static func clampedAlpha(
        base: Float,
        quality: Float,
        penalty: Float,
        scale: Float,
        floor: Float,
        ceiling: Float
    ) -> Float {
        min(max(base + quality * penalty * scale, floor), ceiling)
    }

    /// Produces a penalty curve that stays at 1 until a threshold, then decays linearly.
    nonisolated static func descendingPenalty(
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

    /// Filters out placeholder / invalid stage positions before they influence statistics.
    nonisolated static func isValidStagePosition(_ position: SIMD3<Float>) -> Bool {
        position.x.isFinite &&
            position.y.isFinite &&
            position.z.isFinite &&
            position.y > Self.stageStabilizerTuning.invalidStagePositionYThreshold
    }
}

private extension Array {
    nonisolated subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

struct MotionStudioState {
    var presentation: StudioPresentation = .capture
    var statusText = L10n.statusStandInFrame
    var isRecording = false
    var isPlaying = false
    var recordedFrameCount = 0
    var recordingDuration: TimeInterval = 0
    var clipDuration: TimeInterval = 0
    var hasClip = false
}
