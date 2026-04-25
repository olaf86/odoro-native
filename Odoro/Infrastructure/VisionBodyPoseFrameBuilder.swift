//
//  VisionBodyPoseFrameBuilder.swift
//  Odoro
//

import ARKit
import Foundation
import Vision

enum VisionBodyPoseFrameBuilder {
    private static let skeletonDefinition = ARSkeletonDefinition.defaultBody3D
    private static let neutralJointPositions: [SIMD3<Float>] = {
        let neutral = ARSkeletonDefinition.defaultBody3D.neutralBodySkeleton3D?.jointModelTransforms ?? []
        return neutral.map { transform in
            let translation = transform.columns.3
            return SIMD3<Float>(translation.x, translation.y, translation.z)
        }
    }()

    static func makeFrame(from observation: VNHumanBodyPoseObservation, at time: TimeInterval) -> MotionFrame? {
        guard let points = try? observation.recognizedPoints(.all) else {
            return nil
        }

        guard
            let leftShoulder = stagePosition(for: .leftShoulder, in: points),
            let rightShoulder = stagePosition(for: .rightShoulder, in: points)
        else {
            return nil
        }

        let shoulderCenter = (leftShoulder + rightShoulder) * 0.5
        let root = shoulderCenter + SIMD3<Float>(0, -0.30, 0.02)
        let head = stagePosition(for: .nose, in: points) ?? shoulderCenter + SIMD3<Float>(0, 0.26, 0.03)

        let leftElbow = stagePosition(for: .leftElbow, in: points) ?? leftShoulder + SIMD3<Float>(-0.18, -0.18, 0.02)
        let rightElbow = stagePosition(for: .rightElbow, in: points) ?? rightShoulder + SIMD3<Float>(0.18, -0.18, 0.02)
        let leftHand = stagePosition(for: .leftWrist, in: points) ?? leftElbow + SIMD3<Float>(-0.18, -0.14, 0)
        let rightHand = stagePosition(for: .rightWrist, in: points) ?? rightElbow + SIMD3<Float>(0.18, -0.14, 0)
        let leftUpperArm = (leftShoulder + leftElbow) * 0.5
        let rightUpperArm = (rightShoulder + rightElbow) * 0.5

        let leftHip = root + SIMD3<Float>(-0.12, -0.02, 0)
        let rightHip = root + SIMD3<Float>(0.12, -0.02, 0)
        let leftKnee = leftHip + SIMD3<Float>(-0.02, -0.36, 0.04)
        let rightKnee = rightHip + SIMD3<Float>(0.02, -0.36, -0.04)
        let leftFoot = leftKnee + SIMD3<Float>(0, -0.38, 0.05)
        let rightFoot = rightKnee + SIMD3<Float>(0, -0.38, 0.05)

        var joints = neutralJointPositions
        if joints.count != skeletonDefinition.jointNames.count {
            joints = Array(repeating: SIMD3<Float>(0, -10, 0), count: skeletonDefinition.jointNames.count)
        }

        setJoint(.root, to: root, in: &joints)
        setJoint(.head, to: head, in: &joints)
        setJoint(.leftShoulder, to: leftShoulder, in: &joints)
        setJoint(.rightShoulder, to: rightShoulder, in: &joints)
        setJoint(named: "left_arm_joint", to: leftUpperArm, in: &joints)
        setJoint(named: "right_arm_joint", to: rightUpperArm, in: &joints)
        setJoint(named: "left_forearm_joint", to: leftElbow, in: &joints)
        setJoint(named: "right_forearm_joint", to: rightElbow, in: &joints)
        setJoint(.leftHand, to: leftHand, in: &joints)
        setJoint(.rightHand, to: rightHand, in: &joints)
        setJoint(named: "left_upLeg_joint", to: leftHip, in: &joints)
        setJoint(named: "right_upLeg_joint", to: rightHip, in: &joints)
        setJoint(named: "left_leg_joint", to: leftKnee, in: &joints)
        setJoint(named: "right_leg_joint", to: rightKnee, in: &joints)
        setJoint(.leftFoot, to: leftFoot, in: &joints)
        setJoint(.rightFoot, to: rightFoot, in: &joints)

        return MotionFrame(time: time, jointPositions: joints)
    }

    private static func stagePosition(
        for jointName: VNHumanBodyPoseObservation.JointName,
        in points: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint]
    ) -> SIMD3<Float>? {
        guard let point = points[jointName], point.confidence > 0.15 else {
            return nil
        }

        let x = (Float(point.x) - 0.5) * 1.6
        let y = Float(point.y) * 1.8 + 0.05
        return SIMD3<Float>(x, y, 0)
    }

    private static func setJoint(
        _ jointName: ARSkeleton.JointName,
        to position: SIMD3<Float>,
        in joints: inout [SIMD3<Float>]
    ) {
        let index = skeletonDefinition.index(for: jointName)
        guard index != NSNotFound, joints.indices.contains(index) else {
            return
        }

        joints[index] = position
    }

    private static func setJoint(
        named rawValue: String,
        to position: SIMD3<Float>,
        in joints: inout [SIMD3<Float>]
    ) {
        setJoint(ARSkeleton.JointName(rawValue: rawValue), to: position, in: &joints)
    }
}
