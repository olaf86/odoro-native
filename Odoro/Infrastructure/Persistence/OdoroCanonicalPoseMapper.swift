//
//  OdoroCanonicalPoseMapper.swift
//  Odoro
//

import ARKit
import Foundation
import simd

enum OdoroCanonicalPoseMapper {
    private static let skeletonDefinition = ARSkeletonDefinition.defaultBody3D

    static func map(frame: MotionFrame) -> ([MotionPayloadVector3], [OdoroJointStatus]) {
        let leftShoulder = resolvedPosition(for: .leftShoulder, in: frame)
        let rightShoulder = resolvedPosition(for: .rightShoulder, in: frame)
        let leftHip = resolvedPosition(named: "left_upLeg_joint", in: frame)
        let rightHip = resolvedPosition(named: "right_upLeg_joint", in: frame)
        let shoulderCenter = midpoint(leftShoulder, rightShoulder)

        let root = resolvedPosition(for: .root, in: frame) ?? midpoint(leftHip, rightHip)
        let head = resolvedPosition(for: .head, fallbackRawName: "head_joint", in: frame)
        let nose = resolvedPosition(named: "nose_joint", in: frame)

        let mappedJoints: [(SIMD3<Float>, OdoroJointStatus)] = [
            required(root, fallback: .zero, status: root == nil ? .missing : .observed),
            required(head, fallback: shoulderCenter ?? .zero, status: head == nil ? .missing : .observed),
            required(nose, fallback: head ?? shoulderCenter ?? .zero, status: nose == nil ? .missing : .observed),
            required(leftShoulder, fallback: .zero, status: leftShoulder == nil ? .missing : .observed),
            required(rightShoulder, fallback: .zero, status: rightShoulder == nil ? .missing : .observed),
            required(resolvedPosition(named: "left_arm_joint", in: frame), fallback: leftShoulder ?? .zero, status: .mapped),
            required(resolvedPosition(named: "right_arm_joint", in: frame), fallback: rightShoulder ?? .zero, status: .mapped),
            required(resolvedPosition(for: .leftHand, fallbackRawName: "left_hand_joint", in: frame), fallback: resolvedPosition(named: "left_arm_joint", in: frame) ?? leftShoulder ?? .zero, status: .mapped),
            required(resolvedPosition(for: .rightHand, fallbackRawName: "right_hand_joint", in: frame), fallback: resolvedPosition(named: "right_arm_joint", in: frame) ?? rightShoulder ?? .zero, status: .mapped),
            required(leftHip, fallback: root ?? .zero, status: leftHip == nil ? .missing : .mapped),
            required(rightHip, fallback: root ?? .zero, status: rightHip == nil ? .missing : .mapped),
            required(resolvedPosition(named: "left_leg_joint", in: frame), fallback: leftHip ?? .zero, status: .mapped),
            required(resolvedPosition(named: "right_leg_joint", in: frame), fallback: rightHip ?? .zero, status: .mapped),
            derivedAnkle(knee: resolvedPosition(named: "left_leg_joint", in: frame), foot: resolvedPosition(for: .leftFoot, fallbackRawName: "left_foot_joint", in: frame)),
            derivedAnkle(knee: resolvedPosition(named: "right_leg_joint", in: frame), foot: resolvedPosition(for: .rightFoot, fallbackRawName: "right_foot_joint", in: frame)),
            required(resolvedPosition(for: .leftFoot, fallbackRawName: "left_foot_joint", in: frame), fallback: resolvedPosition(named: "left_leg_joint", in: frame) ?? leftHip ?? .zero, status: .mapped),
            required(resolvedPosition(for: .rightFoot, fallbackRawName: "right_foot_joint", in: frame), fallback: resolvedPosition(named: "right_leg_joint", in: frame) ?? rightHip ?? .zero, status: .mapped),
        ]

        return (
            mappedJoints.map { MotionPayloadVector3($0.0) },
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
        fallbackRawName: String? = nil,
        in frame: MotionFrame
    ) -> SIMD3<Float>? {
        if let position = position(for: jointName, in: frame) {
            return position
        }

        guard let fallbackRawName else {
            return nil
        }

        return position(for: ARSkeleton.JointName(rawValue: fallbackRawName), in: frame)
    }

    private static func resolvedPosition(named rawValue: String, in frame: MotionFrame) -> SIMD3<Float>? {
        position(for: ARSkeleton.JointName(rawValue: rawValue), in: frame)
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
}
