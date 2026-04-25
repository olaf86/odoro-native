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

private extension MotionClip {
    struct StabilizerState {
        var time: TimeInterval
        var center: SIMD3<Float>
        var localPositions: [SIMD3<Float>?]
        var rotations: [MotionJointRotation?]?
    }

    nonisolated func stageStabilizedFrames() -> [MotionFrame] {
        guard frames.count >= 3, let firstFrame = frames.first else {
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
            let deltaTime = max(frame.time - state.time, 1 / 30)
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

    nonisolated static func qualityScore(for frame: MotionFrame) -> Float {
        guard !frame.jointPositions.isEmpty else {
            return 0
        }

        let validPositions = frame.jointPositions.filter(isValidStagePosition)
        let validRatio = Float(validPositions.count) / Float(frame.jointPositions.count)
        guard validPositions.count >= 2 else {
            return validRatio * 0.25
        }

        let span = Self.span(of: validPositions)
        let maxSpan = max(span.x, span.y, span.z)
        let spanScore: Float
        if maxSpan <= 2.8 {
            spanScore = 1
        } else if maxSpan >= 4.2 {
            spanScore = 0.2
        } else {
            spanScore = 1 - ((maxSpan - 2.8) / 1.4) * 0.8
        }

        return min(max(validRatio * spanScore, 0), 1)
    }

    nonisolated static func centerSmoothingAlpha(quality: Float, centerDelta: Float, deltaTime: TimeInterval) -> Float {
        let interval = max(Float(deltaTime), 1 / 30)
        let speed = centerDelta / interval
        let speedPenalty: Float
        if speed <= 3.5 {
            speedPenalty = 1
        } else if speed >= 7 {
            speedPenalty = 0.18
        } else {
            speedPenalty = 1 - ((speed - 3.5) / 3.5) * 0.82
        }

        return min(max(0.12 + quality * speedPenalty * 0.72, 0.08), 0.92)
    }

    nonisolated static func jointSmoothingAlpha(
        quality: Float,
        observedLocal: SIMD3<Float>,
        previousLocal: SIMD3<Float>?
    ) -> Float {
        guard let previousLocal else {
            return 1
        }

        let localDelta = simd_length(observedLocal - previousLocal)
        let spikePenalty: Float
        if localDelta <= 0.35 {
            spikePenalty = 1
        } else if localDelta >= 1.0 {
            spikePenalty = 0.12
        } else {
            spikePenalty = 1 - ((localDelta - 0.35) / 0.65) * 0.88
        }

        return min(max(0.08 + quality * spikePenalty * 0.76, 0.06), 0.88)
    }

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
            let spikePenalty: Float
            if angularDelta <= 0.45 {
                spikePenalty = 1
            } else if angularDelta >= 1.2 {
                spikePenalty = 0.18
            } else {
                spikePenalty = 1 - ((angularDelta - 0.45) / 0.75) * 0.82
            }

            let alpha = min(max(0.1 + quality * spikePenalty * 0.75, 0.08), 0.9)
            return MotionJointRotation(simd_slerp(previousQuat, observedQuat, alpha))
        }
    }

    nonisolated static func estimatedFloorHeight(in frames: [MotionFrame]) -> Float? {
        let ys = frames
            .flatMap(\.jointPositions)
            .filter(isValidStagePosition)
            .map(\.y)
            .sorted()

        guard !ys.isEmpty else {
            return nil
        }

        return percentile(0.05, in: ys)
    }

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

    nonisolated static func percentile(_ percentile: Float, in sortedValues: [Float]) -> Float {
        guard let first = sortedValues.first, sortedValues.count > 1 else {
            return sortedValues.first ?? 0
        }

        let clampedPercentile = min(max(percentile, 0), 1)
        let index = Int((Float(sortedValues.count - 1) * clampedPercentile).rounded(.down))
        return sortedValues[safe: index] ?? first
    }

    nonisolated static func angleBetween(_ lhs: simd_quatf, _ rhs: simd_quatf) -> Float {
        let dot = abs(simd_dot(lhs.vector, rhs.vector))
        return 2 * acos(min(max(dot, -1), 1))
    }

    nonisolated static func mix(_ lhs: SIMD3<Float>, _ rhs: SIMD3<Float>, alpha: Float) -> SIMD3<Float> {
        lhs + (rhs - lhs) * alpha
    }

    nonisolated static func isValidStagePosition(_ position: SIMD3<Float>) -> Bool {
        position.x.isFinite && position.y.isFinite && position.z.isFinite && position.y > -5
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
