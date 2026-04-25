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
        let centerVelocityBlendAlpha: Float = 0.35

        let localDeltaFullPenaltyUpperBound: Float = 0.35
        let localDeltaDegradedPenaltyUpperBound: Float = 1.0
        let localDeltaMinimumPenalty: Float = 0.12
        let jointAlphaFloor: Float = 0.06
        let jointAlphaBase: Float = 0.08
        let jointAlphaScale: Float = 0.76
        let jointAlphaCeiling: Float = 0.88
        let velocityBlendAlpha: Float = 0.35

        let jointVelocityFullUpperBound: Float = 2.4
        let jointVelocityDegradedUpperBound: Float = 6.5
        let jointVelocityMinimumPenalty: Float = 0.12
        let jointAccelerationFullUpperBound: Float = 28
        let jointAccelerationDegradedUpperBound: Float = 88
        let jointAccelerationMinimumPenalty: Float = 0.12
        let jointPredictionErrorFullUpperBound: Float = 0.12
        let jointPredictionErrorDegradedUpperBound: Float = 0.45
        let jointPredictionErrorMinimumPenalty: Float = 0.15

        let rotationDeltaFullPenaltyUpperBound: Float = 0.45
        let rotationDeltaDegradedPenaltyUpperBound: Float = 1.2
        let rotationDeltaMinimumPenalty: Float = 0.18
        let rotationAlphaFloor: Float = 0.08
        let rotationAlphaBase: Float = 0.1
        let rotationAlphaScale: Float = 0.75
        let rotationAlphaCeiling: Float = 0.9

        let constraintActivationErrorRatio: Float = 0.08
        let constraintStrengthBase: Float = 0.32
        let constraintStrengthLowConfidenceBoost: Float = 0.58

        let floorHeightPercentile: Float = 0.05
        let floorTrackingAlpha: Float = 0.28

        let footContactHeightTolerance: Float = 0.05
        let footContactLiftTolerance: Float = 0.1
        let footContactVerticalSpeedUpperBound: Float = 0.45
        let footContactHorizontalSpeedUpperBound: Float = 0.9
        let footContactMinimumConfidence: Float = 0.28
        let footContactPinStrength: Float = 0.82

        nonisolated init() {}
    }

    private struct State {
        var time: TimeInterval
        var center: SIMD3<Float>
        var centerVelocity: SIMD3<Float>
        var localPositions: [SIMD3<Float>?]
        var localVelocities: [SIMD3<Float>?]
        var rotations: [MotionJointRotation?]?
        var floorHeight: Float?
        var footContacts: [Int: FootContactState]
    }

    private struct FootContactState: Sendable {
        var pinnedPosition: SIMD3<Float>
        var framesActive: Int
    }

    private struct CanonicalRig: Sendable {
        let bones: [(parentIndex: Int, childIndex: Int)]
        let footIndices: [Int]
        let floorIndices: [Int]
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
    /// This is not a Kalman filter. It combines:
    /// - joint-level observation confidence,
    /// - predictive temporal smoothing,
    /// - canonical bone-length constraints when available,
    /// - foot contact pinning near the floor.
    nonisolated func stabilize(_ clip: MotionClip) -> [MotionFrame] {
        guard clip.frames.count >= tuning.minimumFrameCount, let firstFrame = clip.frames.first else {
            return clip.frames
        }

        let canonicalRig = canonicalRig(forJointCount: firstFrame.jointPositions.count)
        let canonicalReferenceBoneLengths = canonicalRig.map { referenceBoneLengths(for: $0, frames: clip.frames) } ?? [:]
        let initialFloorHeight = estimatedFloorHeight(in: Array(clip.frames.prefix(8)))

        var state = State(
            time: firstFrame.time,
            center: qualityEvaluator.robustCenter(of: firstFrame.jointPositions) ?? .zero,
            centerVelocity: .zero,
            localPositions: Array(repeating: nil, count: firstFrame.jointPositions.count),
            localVelocities: Array(repeating: nil, count: firstFrame.jointPositions.count),
            rotations: firstFrame.jointRotations,
            floorHeight: initialFloorHeight,
            footContacts: [:]
        )

        return clip.frames.map { frame in
            let assessment = qualityEvaluator.assess(frame)
            let previousCenter = state.center
            let previousWorldPositions = worldPositions(from: state, center: previousCenter)
            let deltaTime = max(frame.time - state.time, tuning.fallbackDeltaTime)
            let interval = Float(deltaTime)

            let observedCenter = assessment.robustCenter ?? state.center
            let predictedCenter = previousCenter + state.centerVelocity * interval
            let centerAlpha = centerSmoothingAlpha(
                quality: assessment.score,
                centerDelta: simd_length(observedCenter - previousCenter),
                deltaTime: deltaTime
            )
            state.center = mix(predictedCenter, observedCenter, alpha: centerAlpha)
            let resolvedCenterVelocity = (state.center - previousCenter) / interval
            state.centerVelocity = mix(
                state.centerVelocity,
                resolvedCenterVelocity,
                alpha: tuning.centerVelocityBlendAlpha
            )

            var jointPositions = Array(repeating: SIMD3<Float>.zero, count: frame.jointPositions.count)
            var jointConfidences = normalizedJointBaseScores(
                assessment.jointScores,
                expectedCount: frame.jointPositions.count
            )

            for (index, position) in frame.jointPositions.enumerated() {
                let previousLocal = state.localPositions[safe: index].flatMap { $0 }
                let previousVelocity = state.localVelocities[safe: index].flatMap { $0 }
                let fallbackLocal = previousLocal.map {
                    $0 + (previousVelocity ?? .zero) * interval
                }

                let isValidPosition = assessment.validPositionMask.indices.contains(index)
                    ? assessment.validPositionMask[index]
                    : false

                guard isValidPosition else {
                    if let fallbackLocal {
                        jointPositions[index] = state.center + fallbackLocal
                        state.localPositions[index] = fallbackLocal
                    } else {
                        jointPositions[index] = position
                    }
                    jointConfidences[index] = 0
                    continue
                }

                let observedLocal = position - observedCenter
                let referenceLocal = fallbackLocal ?? previousLocal ?? observedLocal
                let confidence = jointObservationConfidence(
                    baseConfidence: jointConfidences[index],
                    observedLocal: observedLocal,
                    previousLocal: previousLocal,
                    previousVelocity: previousVelocity,
                    deltaTime: deltaTime
                )
                let jointAlpha = jointSmoothingAlpha(
                    quality: confidence,
                    observedLocal: observedLocal,
                    previousLocal: referenceLocal
                )
                let smoothedLocal = mix(referenceLocal, observedLocal, alpha: jointAlpha)
                jointPositions[index] = state.center + smoothedLocal
                jointConfidences[index] = confidence

                if let previousLocal {
                    let observedVelocity = (smoothedLocal - previousLocal) / interval
                    state.localVelocities[index] = previousVelocity.map {
                        mix($0, observedVelocity, alpha: tuning.velocityBlendAlpha)
                    } ?? observedVelocity
                } else {
                    state.localVelocities[index] = .zero
                }
                state.localPositions[index] = smoothedLocal
            }

            if let canonicalRig {
                if let updatedFloorHeight = updatedFloorHeight(
                    currentFloor: state.floorHeight,
                    positions: jointPositions,
                    rig: canonicalRig
                ) {
                    state.floorHeight = updatedFloorHeight
                }

                jointPositions = constrainedCanonicalJointPositions(
                    positions: jointPositions,
                    confidences: jointConfidences,
                    referenceBoneLengths: canonicalReferenceBoneLengths,
                    rig: canonicalRig
                )

                if let floorHeight = state.floorHeight {
                    let contactResult = footContactAdjustedPositions(
                        positions: jointPositions,
                        confidences: jointConfidences,
                        previousWorldPositions: previousWorldPositions,
                        floorHeight: floorHeight,
                        deltaTime: deltaTime,
                        rig: canonicalRig,
                        activeContacts: state.footContacts
                    )
                    jointPositions = constrainedCanonicalJointPositions(
                        positions: contactResult.positions,
                        confidences: jointConfidences,
                        referenceBoneLengths: canonicalReferenceBoneLengths,
                        rig: canonicalRig
                    )
                    state.footContacts = contactResult.contacts
                }
            }

            // Reflect post-constraint/contact positions back into local state so the
            // next frame predicts from the final rendered pose instead of the raw one.
            for index in jointPositions.indices {
                let finalPosition = jointPositions[index]
                guard qualityEvaluator.isValidStagePosition(finalPosition) else {
                    continue
                }

                let finalLocal = finalPosition - state.center
                if let previousLocal = state.localPositions[safe: index].flatMap({ $0 }) {
                    let observedVelocity = (finalLocal - previousLocal) / interval
                    let previousVelocity = state.localVelocities[safe: index].flatMap { $0 } ?? .zero
                    state.localVelocities[index] = mix(
                        previousVelocity,
                        observedVelocity,
                        alpha: tuning.velocityBlendAlpha
                    )
                }
                state.localPositions[index] = finalLocal
            }

            let jointRotations = smoothedRotations(
                observed: frame.jointRotations,
                previous: state.rotations,
                fallbackQuality: assessment.score,
                jointQualities: jointConfidences
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
        fallbackQuality: Float,
        jointQualities: [Float]
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

            let quality = jointQualities[safe: index] ?? fallbackQuality
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
    private nonisolated func normalizedJointBaseScores(_ jointScores: [Float], expectedCount: Int) -> [Float] {
        if jointScores.count == expectedCount {
            return jointScores
        }

        let trimmed = Array(jointScores.prefix(expectedCount))
        if trimmed.count == expectedCount {
            return trimmed
        }

        return trimmed + Array(repeating: 0, count: expectedCount - trimmed.count)
    }

    private nonisolated func jointObservationConfidence(
        baseConfidence: Float,
        observedLocal: SIMD3<Float>,
        previousLocal: SIMD3<Float>?,
        previousVelocity: SIMD3<Float>?,
        deltaTime: TimeInterval
    ) -> Float {
        guard let previousLocal else {
            return baseConfidence
        }

        let interval = max(Float(deltaTime), Float(tuning.fallbackDeltaTime))
        let observedVelocity = (observedLocal - previousLocal) / interval
        let velocityPenalty = descendingPenalty(
            value: simd_length(observedVelocity),
            fullPenaltyUpperBound: tuning.jointVelocityFullUpperBound,
            degradedPenaltyUpperBound: tuning.jointVelocityDegradedUpperBound,
            minimumPenalty: tuning.jointVelocityMinimumPenalty
        )

        let accelerationPenalty: Float
        let predictionPenalty: Float

        if let previousVelocity {
            let acceleration = simd_length((observedVelocity - previousVelocity) / interval)
            accelerationPenalty = descendingPenalty(
                value: acceleration,
                fullPenaltyUpperBound: tuning.jointAccelerationFullUpperBound,
                degradedPenaltyUpperBound: tuning.jointAccelerationDegradedUpperBound,
                minimumPenalty: tuning.jointAccelerationMinimumPenalty
            )

            let predictedLocal = previousLocal + previousVelocity * interval
            let predictionError = simd_length(observedLocal - predictedLocal)
            predictionPenalty = descendingPenalty(
                value: predictionError,
                fullPenaltyUpperBound: tuning.jointPredictionErrorFullUpperBound,
                degradedPenaltyUpperBound: tuning.jointPredictionErrorDegradedUpperBound,
                minimumPenalty: tuning.jointPredictionErrorMinimumPenalty
            )
        } else {
            accelerationPenalty = 1
            predictionPenalty = 1
        }

        return min(max(baseConfidence * velocityPenalty * accelerationPenalty * predictionPenalty, 0), 1)
    }

    private nonisolated func canonicalRig(forJointCount jointCount: Int) -> CanonicalRig? {
        guard jointCount == OdoroSkeletonDefinition.jointCount else {
            return nil
        }

        let root = OdoroSkeletonDefinition.index(of: .root)
        let head = OdoroSkeletonDefinition.index(of: .head)
        let nose = OdoroSkeletonDefinition.index(of: .nose)
        let leftShoulder = OdoroSkeletonDefinition.index(of: .leftShoulder)
        let rightShoulder = OdoroSkeletonDefinition.index(of: .rightShoulder)
        let leftElbow = OdoroSkeletonDefinition.index(of: .leftElbow)
        let rightElbow = OdoroSkeletonDefinition.index(of: .rightElbow)
        let leftWrist = OdoroSkeletonDefinition.index(of: .leftWrist)
        let rightWrist = OdoroSkeletonDefinition.index(of: .rightWrist)
        let leftHip = OdoroSkeletonDefinition.index(of: .leftHip)
        let rightHip = OdoroSkeletonDefinition.index(of: .rightHip)
        let leftKnee = OdoroSkeletonDefinition.index(of: .leftKnee)
        let rightKnee = OdoroSkeletonDefinition.index(of: .rightKnee)
        let leftAnkle = OdoroSkeletonDefinition.index(of: .leftAnkle)
        let rightAnkle = OdoroSkeletonDefinition.index(of: .rightAnkle)
        let leftFoot = OdoroSkeletonDefinition.index(of: .leftFoot)
        let rightFoot = OdoroSkeletonDefinition.index(of: .rightFoot)

        return CanonicalRig(
            bones: [
                (parentIndex: root, childIndex: head),
                (parentIndex: head, childIndex: nose),
                (parentIndex: root, childIndex: leftShoulder),
                (parentIndex: root, childIndex: rightShoulder),
                (parentIndex: leftShoulder, childIndex: leftElbow),
                (parentIndex: rightShoulder, childIndex: rightElbow),
                (parentIndex: leftElbow, childIndex: leftWrist),
                (parentIndex: rightElbow, childIndex: rightWrist),
                (parentIndex: root, childIndex: leftHip),
                (parentIndex: root, childIndex: rightHip),
                (parentIndex: leftHip, childIndex: leftKnee),
                (parentIndex: rightHip, childIndex: rightKnee),
                (parentIndex: leftKnee, childIndex: leftAnkle),
                (parentIndex: rightKnee, childIndex: rightAnkle),
                (parentIndex: leftAnkle, childIndex: leftFoot),
                (parentIndex: rightAnkle, childIndex: rightFoot),
            ],
            footIndices: [leftFoot, rightFoot],
            floorIndices: [leftAnkle, rightAnkle, leftFoot, rightFoot]
        )
    }

    private nonisolated func referenceBoneLengths(
        for rig: CanonicalRig,
        frames: [MotionFrame]
    ) -> [Int: Float] {
        var samples = Dictionary(uniqueKeysWithValues: rig.bones.map { (boneKey(parentIndex: $0.parentIndex, childIndex: $0.childIndex), [Float]()) })

        for frame in frames.prefix(12) {
            for bone in rig.bones {
                guard
                    frame.jointPositions.indices.contains(bone.parentIndex),
                    frame.jointPositions.indices.contains(bone.childIndex)
                else {
                    continue
                }

                let parent = frame.jointPositions[bone.parentIndex]
                let child = frame.jointPositions[bone.childIndex]
                guard
                    qualityEvaluator.isValidStagePosition(parent),
                    qualityEvaluator.isValidStagePosition(child)
                else {
                    continue
                }

                samples[boneKey(parentIndex: bone.parentIndex, childIndex: bone.childIndex), default: []]
                    .append(simd_distance(parent, child))
            }
        }

        return samples.reduce(into: [:]) { result, item in
            guard let referenceLength = median(item.value), referenceLength > 0.0001 else {
                return
            }
            result[item.key] = referenceLength
        }
    }

    private nonisolated func constrainedCanonicalJointPositions(
        positions: [SIMD3<Float>],
        confidences: [Float],
        referenceBoneLengths: [Int: Float],
        rig: CanonicalRig
    ) -> [SIMD3<Float>] {
        var constrained = positions

        for bone in rig.bones {
            guard
                constrained.indices.contains(bone.parentIndex),
                constrained.indices.contains(bone.childIndex),
                let targetLength = referenceBoneLengths[
                    boneKey(parentIndex: bone.parentIndex, childIndex: bone.childIndex)
                ]
            else {
                continue
            }

            let parent = constrained[bone.parentIndex]
            let child = constrained[bone.childIndex]
            guard
                qualityEvaluator.isValidStagePosition(parent),
                qualityEvaluator.isValidStagePosition(child)
            else {
                continue
            }

            let delta = child - parent
            let currentLength = simd_length(delta)
            guard currentLength > 0.0001 else {
                continue
            }

            let errorRatio = abs(currentLength - targetLength) / max(targetLength, 0.0001)
            let parentConfidence = confidences[safe: bone.parentIndex] ?? 0
            let childConfidence = confidences[safe: bone.childIndex] ?? 0
            let minimumConfidence = min(parentConfidence, childConfidence)

            guard
                errorRatio >= tuning.constraintActivationErrorRatio ||
                minimumConfidence < 0.72
            else {
                continue
            }

            let lowConfidence = 1 - minimumConfidence
            let strength = min(
                1,
                tuning.constraintStrengthBase + lowConfidence * tuning.constraintStrengthLowConfidenceBoost
            )
            let targetChild = parent + simd_normalize(delta) * targetLength
            let childWeight = max(0.2, 1 - childConfidence * 0.7)
            constrained[bone.childIndex] = mix(child, targetChild, alpha: strength * childWeight)
        }

        return constrained
    }

    private nonisolated func updatedFloorHeight(
        currentFloor: Float?,
        positions: [SIMD3<Float>],
        rig: CanonicalRig
    ) -> Float? {
        let ys = rig.floorIndices
            .compactMap { index -> Float? in
                guard positions.indices.contains(index) else {
                    return nil
                }

                let position = positions[index]
                return qualityEvaluator.isValidStagePosition(position) ? position.y : nil
            }
            .sorted()

        guard !ys.isEmpty else {
            return currentFloor
        }

        let candidate = percentile(tuning.floorHeightPercentile, in: ys)
        guard let currentFloor else {
            return candidate
        }

        return currentFloor + (candidate - currentFloor) * tuning.floorTrackingAlpha
    }

    private nonisolated func footContactAdjustedPositions(
        positions: [SIMD3<Float>],
        confidences: [Float],
        previousWorldPositions: [SIMD3<Float>?],
        floorHeight: Float,
        deltaTime: TimeInterval,
        rig: CanonicalRig,
        activeContacts: [Int: FootContactState]
    ) -> (positions: [SIMD3<Float>], contacts: [Int: FootContactState]) {
        var adjusted = positions
        var contacts = activeContacts
        let interval = max(Float(deltaTime), Float(tuning.fallbackDeltaTime))

        for footIndex in rig.footIndices {
            guard adjusted.indices.contains(footIndex) else {
                contacts.removeValue(forKey: footIndex)
                continue
            }

            let current = adjusted[footIndex]
            guard qualityEvaluator.isValidStagePosition(current) else {
                contacts.removeValue(forKey: footIndex)
                continue
            }

            let confidence = confidences[safe: footIndex] ?? 0
            let previous = previousWorldPositions[safe: footIndex].flatMap { $0 }
            let velocity = previous.map { (current - $0) / interval } ?? .zero
            let horizontalSpeed = simd_length(SIMD2<Float>(velocity.x, velocity.z))
            let verticalSpeed = abs(velocity.y)
            let stickyCorrectedPosition = SIMD3<Float>(current.x, floorHeight, current.z)

            if var contact = contacts[footIndex] {
                let canStayPinned =
                    current.y <= floorHeight + tuning.footContactLiftTolerance &&
                    confidence >= tuning.footContactMinimumConfidence * 0.5 &&
                    verticalSpeed <= tuning.footContactVerticalSpeedUpperBound * 1.6

                if canStayPinned {
                    let corrected = SIMD3<Float>(
                        contact.pinnedPosition.x,
                        floorHeight,
                        contact.pinnedPosition.z
                    )
                    adjusted[footIndex] = mix(current, corrected, alpha: tuning.footContactPinStrength)
                    contact.framesActive += 1
                    contact.pinnedPosition = corrected
                    contacts[footIndex] = contact
                    continue
                }

                contacts.removeValue(forKey: footIndex)
            }

            let shouldActivate =
                confidence >= tuning.footContactMinimumConfidence &&
                current.y <= floorHeight + tuning.footContactHeightTolerance &&
                verticalSpeed <= tuning.footContactVerticalSpeedUpperBound &&
                horizontalSpeed <= tuning.footContactHorizontalSpeedUpperBound

            guard shouldActivate else {
                continue
            }

            adjusted[footIndex] = mix(current, stickyCorrectedPosition, alpha: tuning.footContactPinStrength)
            contacts[footIndex] = FootContactState(
                pinnedPosition: SIMD3<Float>(current.x, floorHeight, current.z),
                framesActive: 1
            )
        }

        return (adjusted, contacts)
    }

    private nonisolated func worldPositions(from state: State, center: SIMD3<Float>) -> [SIMD3<Float>?] {
        state.localPositions.map { localPosition in
            localPosition.map { center + $0 }
        }
    }

    private nonisolated func median(_ values: [Float]) -> Float? {
        guard !values.isEmpty else {
            return nil
        }

        let sorted = values.sorted()
        let middle = sorted.count / 2

        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) * 0.5
        }

        return sorted[middle]
    }

    /// Produces a penalty curve that stays at 1 until a threshold, then decays linearly.
    private nonisolated func boneKey(parentIndex: Int, childIndex: Int) -> Int {
        (parentIndex << 8) ^ childIndex
    }

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
