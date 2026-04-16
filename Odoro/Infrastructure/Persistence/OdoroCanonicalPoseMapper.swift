//
//  OdoroCanonicalPoseMapper.swift
//  Odoro
//

import ARKit
import Foundation
import simd

enum OdoroCanonicalPoseMapper {
    private static let skeletonDefinition = ARSkeletonDefinition.defaultBody3D
    private enum JointNames {
        static let head = ARSkeleton.JointName(rawValue: "head_joint")
        static let nose = ARSkeleton.JointName(rawValue: "nose_joint")
        static let leftArm = ARSkeleton.JointName(rawValue: "left_arm_joint")
        static let rightArm = ARSkeleton.JointName(rawValue: "right_arm_joint")
        static let leftHand = ARSkeleton.JointName(rawValue: "left_hand_joint")
        static let rightHand = ARSkeleton.JointName(rawValue: "right_hand_joint")
        static let leftUpLeg = ARSkeleton.JointName(rawValue: "left_upLeg_joint")
        static let rightUpLeg = ARSkeleton.JointName(rawValue: "right_upLeg_joint")
        static let leftLeg = ARSkeleton.JointName(rawValue: "left_leg_joint")
        static let rightLeg = ARSkeleton.JointName(rawValue: "right_leg_joint")
        static let leftFoot = ARSkeleton.JointName(rawValue: "left_foot_joint")
        static let rightFoot = ARSkeleton.JointName(rawValue: "right_foot_joint")
    }

    static func map(frame: MotionFrame) -> (
        positions: [MotionPayloadVector3],
        rotations: [MotionJointRotation?]?,
        statuses: [OdoroJointStatus]
    ) {
        let leftShoulder = resolvedPosition(for: .leftShoulder, in: frame)
        let rightShoulder = resolvedPosition(for: .rightShoulder, in: frame)
        let leftHip = resolvedPosition(for: JointNames.leftUpLeg, in: frame)
        let rightHip = resolvedPosition(for: JointNames.rightUpLeg, in: frame)
        let shoulderCenter = midpoint(leftShoulder, rightShoulder)

        let root = resolvedPosition(for: .root, in: frame) ?? midpoint(leftHip, rightHip)
        let head = resolvedPosition(for: .head, fallbackJointName: JointNames.head, in: frame)
        let nose = resolvedPosition(for: JointNames.nose, in: frame)

        let headRotation = resolvedRotation(for: .head, fallbackJointName: JointNames.head, in: frame)
        let leftHandRotation = resolvedRotation(for: .leftHand, fallbackJointName: JointNames.leftHand, in: frame)
        let rightHandRotation = resolvedRotation(for: .rightHand, fallbackJointName: JointNames.rightHand, in: frame)
        let leftFootRotation = resolvedRotation(for: .leftFoot, fallbackJointName: JointNames.leftFoot, in: frame)
        let rightFootRotation = resolvedRotation(for: .rightFoot, fallbackJointName: JointNames.rightFoot, in: frame)
        let mappedJoints: [(SIMD3<Float>, OdoroJointStatus)] = [
            required(root, fallback: .zero, status: root == nil ? .missing : .observed),
            required(head, fallback: shoulderCenter ?? .zero, status: head == nil ? .missing : .observed),
            required(nose, fallback: head ?? shoulderCenter ?? .zero, status: nose == nil ? .missing : .observed),
            required(leftShoulder, fallback: .zero, status: leftShoulder == nil ? .missing : .observed),
            required(rightShoulder, fallback: .zero, status: rightShoulder == nil ? .missing : .observed),
            required(resolvedPosition(for: JointNames.leftArm, in: frame), fallback: leftShoulder ?? .zero, status: .mapped),
            required(resolvedPosition(for: JointNames.rightArm, in: frame), fallback: rightShoulder ?? .zero, status: .mapped),
            required(resolvedPosition(for: .leftHand, fallbackJointName: JointNames.leftHand, in: frame), fallback: resolvedPosition(for: JointNames.leftArm, in: frame) ?? leftShoulder ?? .zero, status: .mapped),
            required(resolvedPosition(for: .rightHand, fallbackJointName: JointNames.rightHand, in: frame), fallback: resolvedPosition(for: JointNames.rightArm, in: frame) ?? rightShoulder ?? .zero, status: .mapped),
            required(leftHip, fallback: root ?? .zero, status: leftHip == nil ? .missing : .mapped),
            required(rightHip, fallback: root ?? .zero, status: rightHip == nil ? .missing : .mapped),
            required(resolvedPosition(for: JointNames.leftLeg, in: frame), fallback: leftHip ?? .zero, status: .mapped),
            required(resolvedPosition(for: JointNames.rightLeg, in: frame), fallback: rightHip ?? .zero, status: .mapped),
            derivedAnkle(knee: resolvedPosition(for: JointNames.leftLeg, in: frame), foot: resolvedPosition(for: .leftFoot, fallbackJointName: JointNames.leftFoot, in: frame)),
            derivedAnkle(knee: resolvedPosition(for: JointNames.rightLeg, in: frame), foot: resolvedPosition(for: .rightFoot, fallbackJointName: JointNames.rightFoot, in: frame)),
            required(resolvedPosition(for: .leftFoot, fallbackJointName: JointNames.leftFoot, in: frame), fallback: resolvedPosition(for: JointNames.leftLeg, in: frame) ?? leftHip ?? .zero, status: .mapped),
            required(resolvedPosition(for: .rightFoot, fallbackJointName: JointNames.rightFoot, in: frame), fallback: resolvedPosition(for: JointNames.rightLeg, in: frame) ?? rightHip ?? .zero, status: .mapped),
        ]
        let mappedRotations = frame.jointRotations.map { _ in
            [
                resolvedRotation(for: .root, in: frame),
                headRotation,
                resolvedRotation(for: JointNames.nose, in: frame) ?? headRotation,
                resolvedRotation(for: .leftShoulder, in: frame),
                resolvedRotation(for: .rightShoulder, in: frame),
                resolvedRotation(for: JointNames.leftArm, in: frame),
                resolvedRotation(for: JointNames.rightArm, in: frame),
                leftHandRotation,
                rightHandRotation,
                resolvedRotation(for: JointNames.leftUpLeg, in: frame),
                resolvedRotation(for: JointNames.rightUpLeg, in: frame),
                resolvedRotation(for: JointNames.leftLeg, in: frame),
                resolvedRotation(for: JointNames.rightLeg, in: frame),
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

    private static func required(
        _ position: SIMD3<Float>?,
        fallback: SIMD3<Float>,
        status: OdoroJointStatus
    ) -> (SIMD3<Float>, OdoroJointStatus) {
        guard let position else {
            return (fallback, .missing)
        }

        return (position, status)
    }

    private static func derivedAnkle(knee: SIMD3<Float>?, foot: SIMD3<Float>?) -> (SIMD3<Float>, OdoroJointStatus) {
        guard let knee, let foot else {
            return (foot ?? knee ?? .zero, .missing)
        }

        return ((knee + foot) * 0.5, .derived)
    }

    private static func midpoint(_ lhs: SIMD3<Float>?, _ rhs: SIMD3<Float>?) -> SIMD3<Float>? {
        guard let lhs, let rhs else {
            return nil
        }

        return (lhs + rhs) * 0.5
    }

    private static func resolvedPosition(
        for jointName: ARSkeleton.JointName,
        fallbackJointName: ARSkeleton.JointName? = nil,
        in frame: MotionFrame
    ) -> SIMD3<Float>? {
        if let position = position(for: jointName, in: frame) {
            return position
        }

        guard let fallbackJointName else {
            return nil
        }

        return position(for: fallbackJointName, in: frame)
    }

    private static func resolvedRotation(
        for jointName: ARSkeleton.JointName,
        fallbackJointName: ARSkeleton.JointName? = nil,
        in frame: MotionFrame
    ) -> MotionJointRotation? {
        if let rotation = rotation(for: jointName, in: frame) {
            return rotation
        }

        guard let fallbackJointName else {
            return nil
        }

        return rotation(for: fallbackJointName, in: frame)
    }

    private static func position(for jointName: ARSkeleton.JointName, in frame: MotionFrame) -> SIMD3<Float>? {
        let index = skeletonDefinition.index(for: jointName)
        guard index != NSNotFound, frame.jointPositions.indices.contains(index) else {
            return nil
        }

        let position = frame.jointPositions[index]
        guard position.x.isFinite, position.y.isFinite, position.z.isFinite, position.y > -5 else {
            return nil
        }

        return position
    }

    private static func rotation(for jointName: ARSkeleton.JointName, in frame: MotionFrame) -> MotionJointRotation? {
        guard let jointRotations = frame.jointRotations else {
            return nil
        }

        let index = skeletonDefinition.index(for: jointName)
        guard index != NSNotFound, jointRotations.indices.contains(index) else {
            return nil
        }

        return jointRotations[index]
    }
}
