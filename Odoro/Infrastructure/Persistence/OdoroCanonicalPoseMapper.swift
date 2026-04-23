//
//  OdoroCanonicalPoseMapper.swift
//  Odoro
//

import ARKit
import Foundation
import simd

enum OdoroCanonicalPoseMapper {
    typealias JointIndexResolver = (ARSkeleton.JointName) -> Int
    typealias MappedFrame = (
        positions: [MotionPayloadVector3],
        rotations: [MotionJointRotation?]?,
        statuses: [OdoroJointStatus]
    )

    private enum JointNames {
        nonisolated static var head: ARSkeleton.JointName { ARSkeleton.JointName(rawValue: "head_joint") }
        nonisolated static var nose: ARSkeleton.JointName { ARSkeleton.JointName(rawValue: "nose_joint") }
        nonisolated static var leftArm: ARSkeleton.JointName { ARSkeleton.JointName(rawValue: "left_arm_joint") }
        nonisolated static var rightArm: ARSkeleton.JointName { ARSkeleton.JointName(rawValue: "right_arm_joint") }
        nonisolated static var leftHand: ARSkeleton.JointName { ARSkeleton.JointName(rawValue: "left_hand_joint") }
        nonisolated static var rightHand: ARSkeleton.JointName { ARSkeleton.JointName(rawValue: "right_hand_joint") }
        nonisolated static var leftUpLeg: ARSkeleton.JointName { ARSkeleton.JointName(rawValue: "left_upLeg_joint") }
        nonisolated static var rightUpLeg: ARSkeleton.JointName { ARSkeleton.JointName(rawValue: "right_upLeg_joint") }
        nonisolated static var leftLeg: ARSkeleton.JointName { ARSkeleton.JointName(rawValue: "left_leg_joint") }
        nonisolated static var rightLeg: ARSkeleton.JointName { ARSkeleton.JointName(rawValue: "right_leg_joint") }
        nonisolated static var leftFoot: ARSkeleton.JointName { ARSkeleton.JointName(rawValue: "left_foot_joint") }
        nonisolated static var rightFoot: ARSkeleton.JointName { ARSkeleton.JointName(rawValue: "right_foot_joint") }
    }

    nonisolated private static var skeletonDefinition: ARSkeletonDefinition {
        ARSkeletonDefinition.defaultBody3D
    }

    nonisolated static func map(frame: MotionFrame) -> MappedFrame {
        map(frame: frame) { skeletonDefinition.index(for: $0) }
    }

    nonisolated static func map(frame: MotionFrame, jointIndex: JointIndexResolver) -> MappedFrame {
        let leftShoulder = resolvedPosition(for: .leftShoulder, in: frame, jointIndex: jointIndex)
        let rightShoulder = resolvedPosition(for: .rightShoulder, in: frame, jointIndex: jointIndex)
        let leftHip = resolvedPosition(for: JointNames.leftUpLeg, in: frame, jointIndex: jointIndex)
        let rightHip = resolvedPosition(for: JointNames.rightUpLeg, in: frame, jointIndex: jointIndex)
        let shoulderCenter = midpoint(leftShoulder, rightShoulder)

        let root = resolvedPosition(for: .root, in: frame, jointIndex: jointIndex) ?? midpoint(leftHip, rightHip)
        let head = resolvedPosition(for: .head, fallbackJointName: JointNames.head, in: frame, jointIndex: jointIndex)
        let nose = resolvedPosition(for: JointNames.nose, in: frame, jointIndex: jointIndex)

        let headRotation = resolvedRotation(for: .head, fallbackJointName: JointNames.head, in: frame, jointIndex: jointIndex)
        let leftHandRotation = resolvedRotation(for: .leftHand, fallbackJointName: JointNames.leftHand, in: frame, jointIndex: jointIndex)
        let rightHandRotation = resolvedRotation(for: .rightHand, fallbackJointName: JointNames.rightHand, in: frame, jointIndex: jointIndex)
        let leftFootRotation = resolvedRotation(for: .leftFoot, fallbackJointName: JointNames.leftFoot, in: frame, jointIndex: jointIndex)
        let rightFootRotation = resolvedRotation(for: .rightFoot, fallbackJointName: JointNames.rightFoot, in: frame, jointIndex: jointIndex)
        let mappedJoints: [(SIMD3<Float>, OdoroJointStatus)] = [
            required(root, fallback: .zero, status: root == nil ? .missing : .observed),
            required(head, fallback: shoulderCenter ?? .zero, status: head == nil ? .missing : .observed),
            required(nose, fallback: head ?? shoulderCenter ?? .zero, status: nose == nil ? .missing : .observed),
            required(leftShoulder, fallback: .zero, status: leftShoulder == nil ? .missing : .observed),
            required(rightShoulder, fallback: .zero, status: rightShoulder == nil ? .missing : .observed),
            required(resolvedPosition(for: JointNames.leftArm, in: frame, jointIndex: jointIndex), fallback: leftShoulder ?? .zero, status: .mapped),
            required(resolvedPosition(for: JointNames.rightArm, in: frame, jointIndex: jointIndex), fallback: rightShoulder ?? .zero, status: .mapped),
            required(resolvedPosition(for: .leftHand, fallbackJointName: JointNames.leftHand, in: frame, jointIndex: jointIndex), fallback: resolvedPosition(for: JointNames.leftArm, in: frame, jointIndex: jointIndex) ?? leftShoulder ?? .zero, status: .mapped),
            required(resolvedPosition(for: .rightHand, fallbackJointName: JointNames.rightHand, in: frame, jointIndex: jointIndex), fallback: resolvedPosition(for: JointNames.rightArm, in: frame, jointIndex: jointIndex) ?? rightShoulder ?? .zero, status: .mapped),
            required(leftHip, fallback: root ?? .zero, status: leftHip == nil ? .missing : .mapped),
            required(rightHip, fallback: root ?? .zero, status: rightHip == nil ? .missing : .mapped),
            required(resolvedPosition(for: JointNames.leftLeg, in: frame, jointIndex: jointIndex), fallback: leftHip ?? .zero, status: .mapped),
            required(resolvedPosition(for: JointNames.rightLeg, in: frame, jointIndex: jointIndex), fallback: rightHip ?? .zero, status: .mapped),
            derivedAnkle(knee: resolvedPosition(for: JointNames.leftLeg, in: frame, jointIndex: jointIndex), foot: resolvedPosition(for: .leftFoot, fallbackJointName: JointNames.leftFoot, in: frame, jointIndex: jointIndex)),
            derivedAnkle(knee: resolvedPosition(for: JointNames.rightLeg, in: frame, jointIndex: jointIndex), foot: resolvedPosition(for: .rightFoot, fallbackJointName: JointNames.rightFoot, in: frame, jointIndex: jointIndex)),
            required(resolvedPosition(for: .leftFoot, fallbackJointName: JointNames.leftFoot, in: frame, jointIndex: jointIndex), fallback: resolvedPosition(for: JointNames.leftLeg, in: frame, jointIndex: jointIndex) ?? leftHip ?? .zero, status: .mapped),
            required(resolvedPosition(for: .rightFoot, fallbackJointName: JointNames.rightFoot, in: frame, jointIndex: jointIndex), fallback: resolvedPosition(for: JointNames.rightLeg, in: frame, jointIndex: jointIndex) ?? rightHip ?? .zero, status: .mapped),
        ]
        let mappedRotations = frame.jointRotations.map { _ in
            [
                resolvedRotation(for: .root, in: frame, jointIndex: jointIndex),
                headRotation,
                resolvedRotation(for: JointNames.nose, in: frame, jointIndex: jointIndex) ?? headRotation,
                resolvedRotation(for: .leftShoulder, in: frame, jointIndex: jointIndex),
                resolvedRotation(for: .rightShoulder, in: frame, jointIndex: jointIndex),
                resolvedRotation(for: JointNames.leftArm, in: frame, jointIndex: jointIndex),
                resolvedRotation(for: JointNames.rightArm, in: frame, jointIndex: jointIndex),
                leftHandRotation,
                rightHandRotation,
                resolvedRotation(for: JointNames.leftUpLeg, in: frame, jointIndex: jointIndex),
                resolvedRotation(for: JointNames.rightUpLeg, in: frame, jointIndex: jointIndex),
                resolvedRotation(for: JointNames.leftLeg, in: frame, jointIndex: jointIndex),
                resolvedRotation(for: JointNames.rightLeg, in: frame, jointIndex: jointIndex),
                leftFootRotation,
                rightFootRotation,
                leftFootRotation,
                rightFootRotation,
            ]
        }

        return (
            mappedJoints.map { MotionPayloadVector3($0.0) },
            mappedRotations,
            mappedJoints.map(\.1)
        )
    }

    nonisolated private static func required(
        _ position: SIMD3<Float>?,
        fallback: SIMD3<Float>,
        status: OdoroJointStatus
    ) -> (SIMD3<Float>, OdoroJointStatus) {
        guard let position else {
            return (fallback, .missing)
        }

        return (position, status)
    }

    nonisolated private static func derivedAnkle(knee: SIMD3<Float>?, foot: SIMD3<Float>?) -> (SIMD3<Float>, OdoroJointStatus) {
        guard let knee, let foot else {
            return (foot ?? knee ?? .zero, .missing)
        }

        return ((knee + foot) * 0.5, .derived)
    }

    nonisolated private static func midpoint(_ lhs: SIMD3<Float>?, _ rhs: SIMD3<Float>?) -> SIMD3<Float>? {
        guard let lhs, let rhs else {
            return nil
        }

        return (lhs + rhs) * 0.5
    }

    nonisolated private static func resolvedPosition(
        for jointName: ARSkeleton.JointName,
        fallbackJointName: ARSkeleton.JointName? = nil,
        in frame: MotionFrame,
        jointIndex: JointIndexResolver
    ) -> SIMD3<Float>? {
        if let position = position(for: jointName, in: frame, jointIndex: jointIndex) {
            return position
        }

        guard let fallbackJointName else {
            return nil
        }

        return position(for: fallbackJointName, in: frame, jointIndex: jointIndex)
    }

    nonisolated private static func resolvedRotation(
        for jointName: ARSkeleton.JointName,
        fallbackJointName: ARSkeleton.JointName? = nil,
        in frame: MotionFrame,
        jointIndex: JointIndexResolver
    ) -> MotionJointRotation? {
        if let rotation = rotation(for: jointName, in: frame, jointIndex: jointIndex) {
            return rotation
        }

        guard let fallbackJointName else {
            return nil
        }

        return rotation(for: fallbackJointName, in: frame, jointIndex: jointIndex)
    }

    nonisolated private static func position(
        for jointName: ARSkeleton.JointName,
        in frame: MotionFrame,
        jointIndex: JointIndexResolver
    ) -> SIMD3<Float>? {
        let index = jointIndex(jointName)
        guard index != NSNotFound, frame.jointPositions.indices.contains(index) else {
            return nil
        }

        let position = frame.jointPositions[index]
        guard position.x.isFinite, position.y.isFinite, position.z.isFinite, position.y > -5 else {
            return nil
        }

        return position
    }

    nonisolated private static func rotation(
        for jointName: ARSkeleton.JointName,
        in frame: MotionFrame,
        jointIndex: JointIndexResolver
    ) -> MotionJointRotation? {
        guard let jointRotations = frame.jointRotations else {
            return nil
        }

        let index = jointIndex(jointName)
        guard index != NSNotFound, jointRotations.indices.contains(index) else {
            return nil
        }

        return jointRotations[index]
    }
}
