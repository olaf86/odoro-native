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
        nonisolated static var leftForearm: ARSkeleton.JointName { ARSkeleton.JointName(rawValue: "left_forearm_joint") }
        nonisolated static var rightForearm: ARSkeleton.JointName { ARSkeleton.JointName(rawValue: "right_forearm_joint") }
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
    nonisolated private static let ankleDistanceRatioFromFootToKnee: Float = 0.08
    nonisolated private static let minimumVectorLength: Float = 0.0001

    nonisolated static func map(frame: MotionFrame) -> MappedFrame {
        map(frame: frame) { skeletonDefinition.index(for: $0) }
    }

    nonisolated static func canonicalizedClip(from clip: MotionClip) -> MotionClip {
        guard !clip.frames.isEmpty else {
            return clip
        }

        let frames = clip.frames.map { frame in
            if frame.jointPositions.count == OdoroSkeletonDefinition.jointCount {
                return frame
            }

            let mappedFrame = map(frame: frame)
            return MotionFrame(
                time: frame.time,
                jointPositions: mappedFrame.positions.map { $0.simdValue },
                jointRotations: mappedFrame.rotations
            )
        }

        return MotionClip(frames: frames)
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
        let leftUpperArm = resolvedPosition(for: JointNames.leftArm, in: frame, jointIndex: jointIndex)
        let rightUpperArm = resolvedPosition(for: JointNames.rightArm, in: frame, jointIndex: jointIndex)
        let leftElbow = resolvedPosition(
            for: JointNames.leftForearm,
            fallbackJointName: JointNames.leftArm,
            in: frame,
            jointIndex: jointIndex
        )
        let rightElbow = resolvedPosition(
            for: JointNames.rightForearm,
            fallbackJointName: JointNames.rightArm,
            in: frame,
            jointIndex: jointIndex
        )
        let leftWrist =
            resolvedPosition(for: .leftHand, fallbackJointName: JointNames.leftHand, in: frame, jointIndex: jointIndex)
            ?? leftElbow
        let rightWrist =
            resolvedPosition(for: .rightHand, fallbackJointName: JointNames.rightHand, in: frame, jointIndex: jointIndex)
            ?? rightElbow

        let headRotation = resolvedRotation(for: .head, fallbackJointName: JointNames.head, in: frame, jointIndex: jointIndex)
        let leftUpperArmRotation = resolvedRotation(for: JointNames.leftArm, in: frame, jointIndex: jointIndex)
        let rightUpperArmRotation = resolvedRotation(for: JointNames.rightArm, in: frame, jointIndex: jointIndex)
        let leftElbowRotation = resolvedRotation(
            for: JointNames.leftForearm,
            fallbackJointName: JointNames.leftArm,
            in: frame,
            jointIndex: jointIndex
        )
        let rightElbowRotation = resolvedRotation(
            for: JointNames.rightForearm,
            fallbackJointName: JointNames.rightArm,
            in: frame,
            jointIndex: jointIndex
        )
        let leftHandRotation = resolvedRotation(for: .leftHand, fallbackJointName: JointNames.leftHand, in: frame, jointIndex: jointIndex)
        let rightHandRotation = resolvedRotation(for: .rightHand, fallbackJointName: JointNames.rightHand, in: frame, jointIndex: jointIndex)
        let leftFootRotation = resolvedRotation(for: .leftFoot, fallbackJointName: JointNames.leftFoot, in: frame, jointIndex: jointIndex)
        let rightFootRotation = resolvedRotation(for: .rightFoot, fallbackJointName: JointNames.rightFoot, in: frame, jointIndex: jointIndex)
        let leftKnee = resolvedPosition(for: JointNames.leftLeg, in: frame, jointIndex: jointIndex)
        let rightKnee = resolvedPosition(for: JointNames.rightLeg, in: frame, jointIndex: jointIndex)
        let leftFoot = resolvedPosition(for: .leftFoot, fallbackJointName: JointNames.leftFoot, in: frame, jointIndex: jointIndex)
        let rightFoot = resolvedPosition(for: .rightFoot, fallbackJointName: JointNames.rightFoot, in: frame, jointIndex: jointIndex)
        let mappedJoints = Dictionary(
            uniqueKeysWithValues: [
                (OdoroJointName.root, required(root, fallback: .zero, status: root == nil ? .missing : .observed)),
                (OdoroJointName.head, required(head, fallback: shoulderCenter ?? .zero, status: head == nil ? .missing : .observed)),
                (OdoroJointName.nose, required(nose, fallback: head ?? shoulderCenter ?? .zero, status: nose == nil ? .missing : .observed)),
                (OdoroJointName.leftShoulder, required(leftShoulder, fallback: .zero, status: leftShoulder == nil ? .missing : .observed)),
                (OdoroJointName.rightShoulder, required(rightShoulder, fallback: .zero, status: rightShoulder == nil ? .missing : .observed)),
                (OdoroJointName.leftElbow, required(leftElbow, fallback: leftUpperArm ?? leftShoulder ?? .zero, status: .mapped)),
                (OdoroJointName.rightElbow, required(rightElbow, fallback: rightUpperArm ?? rightShoulder ?? .zero, status: .mapped)),
                (OdoroJointName.leftWrist, required(leftWrist, fallback: leftElbow ?? leftUpperArm ?? leftShoulder ?? .zero, status: .mapped)),
                (OdoroJointName.rightWrist, required(rightWrist, fallback: rightElbow ?? rightUpperArm ?? rightShoulder ?? .zero, status: .mapped)),
                (OdoroJointName.leftHip, required(leftHip, fallback: root ?? .zero, status: leftHip == nil ? .missing : .mapped)),
                (OdoroJointName.rightHip, required(rightHip, fallback: root ?? .zero, status: rightHip == nil ? .missing : .mapped)),
                (OdoroJointName.leftKnee, required(leftKnee, fallback: leftHip ?? .zero, status: .mapped)),
                (OdoroJointName.rightKnee, required(rightKnee, fallback: rightHip ?? .zero, status: .mapped)),
                (OdoroJointName.leftAnkle, derivedAnkle(knee: leftKnee, foot: leftFoot)),
                (OdoroJointName.rightAnkle, derivedAnkle(knee: rightKnee, foot: rightFoot)),
                (OdoroJointName.leftFoot, required(leftFoot, fallback: leftKnee ?? leftHip ?? .zero, status: .mapped)),
                (OdoroJointName.rightFoot, required(rightFoot, fallback: rightKnee ?? rightHip ?? .zero, status: .mapped)),
                (OdoroJointName.leftUpperArm, required(leftUpperArm, fallback: midpoint(leftShoulder, leftElbow) ?? leftShoulder ?? .zero, status: .mapped)),
                (OdoroJointName.rightUpperArm, required(rightUpperArm, fallback: midpoint(rightShoulder, rightElbow) ?? rightShoulder ?? .zero, status: .mapped)),
            ]
        )
        let mappedRotations = frame.jointRotations.map { _ in
            let values = Dictionary(
                uniqueKeysWithValues: [
                    (OdoroJointName.root, resolvedRotation(for: .root, in: frame, jointIndex: jointIndex)),
                    (OdoroJointName.head, headRotation),
                    (OdoroJointName.nose, resolvedRotation(for: JointNames.nose, in: frame, jointIndex: jointIndex) ?? headRotation),
                    (OdoroJointName.leftShoulder, resolvedRotation(for: .leftShoulder, in: frame, jointIndex: jointIndex)),
                    (OdoroJointName.rightShoulder, resolvedRotation(for: .rightShoulder, in: frame, jointIndex: jointIndex)),
                    (OdoroJointName.leftElbow, leftElbowRotation),
                    (OdoroJointName.rightElbow, rightElbowRotation),
                    (OdoroJointName.leftWrist, leftHandRotation),
                    (OdoroJointName.rightWrist, rightHandRotation),
                    (OdoroJointName.leftHip, resolvedRotation(for: JointNames.leftUpLeg, in: frame, jointIndex: jointIndex)),
                    (OdoroJointName.rightHip, resolvedRotation(for: JointNames.rightUpLeg, in: frame, jointIndex: jointIndex)),
                    (OdoroJointName.leftKnee, resolvedRotation(for: JointNames.leftLeg, in: frame, jointIndex: jointIndex)),
                    (OdoroJointName.rightKnee, resolvedRotation(for: JointNames.rightLeg, in: frame, jointIndex: jointIndex)),
                    (OdoroJointName.leftAnkle, leftFootRotation),
                    (OdoroJointName.rightAnkle, rightFootRotation),
                    (OdoroJointName.leftFoot, leftFootRotation),
                    (OdoroJointName.rightFoot, rightFootRotation),
                    (OdoroJointName.leftUpperArm, leftUpperArmRotation),
                    (OdoroJointName.rightUpperArm, rightUpperArmRotation),
                ]
            )

            return OdoroSkeletonDefinition.jointNames.map { values[$0] ?? nil }
        }

        return (
            OdoroSkeletonDefinition.jointNames.map { jointName in
                MotionPayloadVector3(mappedJoints[jointName]?.0 ?? .zero)
            },
            mappedRotations,
            OdoroSkeletonDefinition.jointNames.map { jointName in
                mappedJoints[jointName]?.1 ?? .missing
            }
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

        let footToKnee = knee - foot
        let footToKneeLength = simd_length(footToKnee)
        guard footToKneeLength > minimumVectorLength else {
            return (foot, .derived)
        }

        let footToKneeDirection = footToKnee / footToKneeLength
        let footToAnkleDistance = footToKneeLength * ankleDistanceRatioFromFootToKnee
        return (foot + footToKneeDirection * footToAnkleDistance, .derived)
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
