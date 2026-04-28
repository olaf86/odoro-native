//
//  RearBody3DEndEffectorInferencePass.swift
//  Odoro
//

import Foundation
import simd

struct DerivedEndEffectorPose: Codable, Sendable, Equatable {
    let pivot: SIMD3<Float>
    let forward: SIMD3<Float>
    let up: SIMD3<Float>
    let confidence: Float
}

struct DerivedFootPoses: Codable, Sendable, Equatable {
    let left: DerivedEndEffectorPose?
    let right: DerivedEndEffectorPose?
    let leftContactWeight: Float
    let rightContactWeight: Float
}

struct DerivedHandPoses: Codable, Sendable, Equatable {
    let left: DerivedEndEffectorPose?
    let right: DerivedEndEffectorPose?
}

struct MotionFrameEndEffectorInference: Codable, Sendable, Equatable {
    let time: TimeInterval
    let feet: DerivedFootPoses
    let hands: DerivedHandPoses
}

struct MotionClipEndEffectorInference: Codable, Sendable, Equatable {
    let frames: [MotionFrameEndEffectorInference]
}

struct RearBody3DEndEffectorInferencePass: Sendable {
    struct Tuning: Sendable {
        let minimumDirectionLength: Float = 0.0001
        let footContactHeightTolerance: Float = 0.06
        let footContactSpeedTolerance: Float = 0.18
        let highConfidence: Float = 0.85
        let mediumConfidence: Float = 0.55
        let lowConfidence: Float = 0.25

        nonisolated init() {}
    }

    let tuning: Tuning

    nonisolated init(tuning: Tuning = .init()) {
        self.tuning = tuning
    }

    nonisolated func infer(clip: MotionClip) -> MotionClipEndEffectorInference {
        MotionClipEndEffectorInference(
            frames: clip.frames.enumerated().map { index, frame in
                inferFrame(frame, at: index, in: clip.frames)
            }
        )
    }

    nonisolated private func inferFrame(
        _ frame: MotionFrame,
        at index: Int,
        in frames: [MotionFrame]
    ) -> MotionFrameEndEffectorInference {
        guard frame.jointPositions.count == OdoroSkeletonDefinition.jointCount else {
            return MotionFrameEndEffectorInference(
                time: frame.time,
                feet: DerivedFootPoses(left: nil, right: nil, leftContactWeight: 0, rightContactWeight: 0),
                hands: DerivedHandPoses(left: nil, right: nil)
            )
        }

        let bodyForwardHint = self.bodyForwardHint(in: frame)
        let leftFoot = inferFootPose(
            side: .left,
            in: frame,
            bodyForwardHint: bodyForwardHint,
            contactWeight: footContactWeight(side: .left, frameIndex: index, frames: frames)
        )
        let rightFoot = inferFootPose(
            side: .right,
            in: frame,
            bodyForwardHint: bodyForwardHint,
            contactWeight: footContactWeight(side: .right, frameIndex: index, frames: frames)
        )
        let leftHand = inferHandPose(side: .left, in: frame, bodyForwardHint: bodyForwardHint)
        let rightHand = inferHandPose(side: .right, in: frame, bodyForwardHint: bodyForwardHint)

        return MotionFrameEndEffectorInference(
            time: frame.time,
            feet: DerivedFootPoses(
                left: leftFoot,
                right: rightFoot,
                leftContactWeight: footContactWeight(side: .left, frameIndex: index, frames: frames),
                rightContactWeight: footContactWeight(side: .right, frameIndex: index, frames: frames)
            ),
            hands: DerivedHandPoses(left: leftHand, right: rightHand)
        )
    }

    nonisolated private func inferFootPose(
        side: BodySide,
        in frame: MotionFrame,
        bodyForwardHint: SIMD3<Float>?,
        contactWeight: Float
    ) -> DerivedEndEffectorPose? {
        guard
            let foot = canonicalPosition(for: side.footJoint, in: frame),
            let ankle = canonicalPosition(for: side.ankleJoint, in: frame)
        else {
            return nil
        }

        let up = normalizedOrNil(ankle - foot) ?? SIMD3<Float>(0, 1, 0)
        let rotationForward = canonicalRotation(for: side.footJoint, in: frame).flatMap {
            projectedDirection($0.simdValue.acting(on: SIMD3<Float>(0, 0, 1)), planeNormal: up)
        }

        let bodyForward = bodyForwardHint.flatMap {
            projectedDirection($0, planeNormal: up)
        }

        let resolvedForward: SIMD3<Float>?
        if let rotationForward {
            if let bodyForward, simd_dot(rotationForward, bodyForward) < 0 {
                resolvedForward = -rotationForward
            } else {
                resolvedForward = rotationForward
            }
        } else {
            resolvedForward = bodyForward
        }

        let forward = resolvedForward ?? orthogonalFallbackDirection(to: up)
        let confidenceBase: Float
        if rotationForward != nil {
            confidenceBase = tuning.highConfidence
        } else if bodyForward != nil {
            confidenceBase = tuning.mediumConfidence
        } else {
            confidenceBase = tuning.lowConfidence
        }

        return DerivedEndEffectorPose(
            pivot: foot,
            forward: forward,
            up: up,
            confidence: min(1, confidenceBase + contactWeight * 0.1)
        )
    }

    nonisolated private func inferHandPose(
        side: BodySide,
        in frame: MotionFrame,
        bodyForwardHint: SIMD3<Float>?
    ) -> DerivedEndEffectorPose? {
        guard
            let wrist = canonicalPosition(for: side.wristJoint, in: frame),
            let elbow = canonicalPosition(for: side.elbowJoint, in: frame)
        else {
            return nil
        }

        let forearmDirection = normalizedOrNil(wrist - elbow) ?? SIMD3<Float>(0, 0, 1)
        let rotationForward = canonicalRotation(for: side.wristJoint, in: frame).flatMap {
            normalizedOrNil($0.simdValue.acting(on: SIMD3<Float>(0, 0, 1)))
        }
        let forward = rotationForward ?? bodyForwardHint ?? forearmDirection
        let bodyRight = bodyRightHint(in: frame)
        let up = normalizedOrNil(simd_cross(bodyRight ?? SIMD3<Float>(1, 0, 0), forward))
            ?? normalizedOrNil(simd_cross(forearmDirection, forward))
            ?? SIMD3<Float>(0, 1, 0)
        let confidence = rotationForward != nil ? tuning.highConfidence : tuning.mediumConfidence

        return DerivedEndEffectorPose(
            pivot: wrist,
            forward: forward,
            up: up,
            confidence: confidence
        )
    }

    nonisolated private func footContactWeight(
        side: BodySide,
        frameIndex: Int,
        frames: [MotionFrame]
    ) -> Float {
        guard
            frames.indices.contains(frameIndex),
            let currentFoot = canonicalPosition(for: side.footJoint, in: frames[frameIndex])
        else {
            return 0
        }

        let previousFrame = frames[max(0, frameIndex - 1)]
        let nextFrame = frames[min(frames.count - 1, frameIndex + 1)]
        let previousFoot = canonicalPosition(for: side.footJoint, in: previousFrame) ?? currentFoot
        let nextFoot = canonicalPosition(for: side.footJoint, in: nextFrame) ?? currentFoot
        let deltaTime = max(nextFrame.time - previousFrame.time, 1.0 / 30.0)
        let velocity = simd_length(nextFoot - previousFoot) / Float(deltaTime)
        let heightPenalty = min(abs(currentFoot.y) / tuning.footContactHeightTolerance, 1)
        let speedPenalty = min(velocity / tuning.footContactSpeedTolerance, 1)

        return max(0, (1 - heightPenalty) * (1 - speedPenalty))
    }

    nonisolated private func bodyForwardHint(in frame: MotionFrame) -> SIMD3<Float>? {
        guard
            let root = canonicalPosition(for: .root, in: frame),
            let nose = canonicalPosition(for: .nose, in: frame) ?? canonicalPosition(for: .head, in: frame)
        else {
            return nil
        }

        let horizontal = SIMD3<Float>(nose.x - root.x, 0, nose.z - root.z)
        return normalizedOrNil(horizontal)
    }

    nonisolated private func bodyRightHint(in frame: MotionFrame) -> SIMD3<Float>? {
        guard
            let leftShoulder = canonicalPosition(for: .leftShoulder, in: frame),
            let rightShoulder = canonicalPosition(for: .rightShoulder, in: frame)
        else {
            return nil
        }

        return normalizedOrNil(rightShoulder - leftShoulder)
    }

    nonisolated private func canonicalPosition(for joint: OdoroJointName, in frame: MotionFrame) -> SIMD3<Float>? {
        let index = OdoroSkeletonDefinition.index(of: joint)
        guard frame.jointPositions.indices.contains(index) else {
            return nil
        }

        let position = frame.jointPositions[index]
        guard position.x.isFinite, position.y.isFinite, position.z.isFinite else {
            return nil
        }

        return position
    }

    nonisolated private func canonicalRotation(for joint: OdoroJointName, in frame: MotionFrame) -> MotionJointRotation? {
        guard let rotations = frame.jointRotations else {
            return nil
        }

        let index = OdoroSkeletonDefinition.index(of: joint)
        guard rotations.indices.contains(index) else {
            return nil
        }

        return rotations[index]
    }

    nonisolated private func projectedDirection(
        _ vector: SIMD3<Float>,
        planeNormal: SIMD3<Float>
    ) -> SIMD3<Float>? {
        let projected = vector - planeNormal * simd_dot(vector, planeNormal)
        return normalizedOrNil(projected)
    }

    nonisolated private func orthogonalFallbackDirection(to normal: SIMD3<Float>) -> SIMD3<Float> {
        let candidate = simd_cross(normal, SIMD3<Float>(1, 0, 0))
        return normalizedOrNil(candidate)
            ?? normalizedOrNil(simd_cross(normal, SIMD3<Float>(0, 0, 1)))
            ?? SIMD3<Float>(0, 0, 1)
    }

    nonisolated private func normalizedOrNil(_ vector: SIMD3<Float>) -> SIMD3<Float>? {
        let length = simd_length(vector)
        guard length > tuning.minimumDirectionLength else {
            return nil
        }

        return vector / length
    }
}

private enum BodySide {
    case left
    case right

    nonisolated var ankleJoint: OdoroJointName {
        switch self {
        case .left: .leftAnkle
        case .right: .rightAnkle
        }
    }

    nonisolated var footJoint: OdoroJointName {
        switch self {
        case .left: .leftFoot
        case .right: .rightFoot
        }
    }

    nonisolated var elbowJoint: OdoroJointName {
        switch self {
        case .left: .leftElbow
        case .right: .rightElbow
        }
    }

    nonisolated var wristJoint: OdoroJointName {
        switch self {
        case .left: .leftWrist
        case .right: .rightWrist
        }
    }
}

private extension simd_quatf {
    nonisolated func acting(on vector: SIMD3<Float>) -> SIMD3<Float> {
        simd_act(self, vector)
    }
}
