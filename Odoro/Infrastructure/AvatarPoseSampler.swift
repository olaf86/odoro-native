//
//  AvatarPoseSampler.swift
//  Odoro

import ARKit

/// Converts MotionFrame data into AvatarDrivePose (canonical world-space).
///
/// Handles both 19-joint canonical frames (post-OdoroCanonicalPoseMapper) and
/// 91-joint ARKit-order frames (rig clips). Also exposes the neutral T-pose
/// derived from ARKit's default body skeleton, which AvatarRigRetargeter uses
/// as the rotation-delta reference so that retargeting is independent of the
/// ARKit joint hierarchy.
struct AvatarPoseSampler: Sendable {
    /// World-space T-pose for every canonical joint, derived from ARKit's neutral body skeleton.
    /// Used as the rotation reference in delta-based retargeting.
    let tPose: AvatarDrivePose

    /// Two identical canonical frames so debug playback can render and loop a neutral pose.
    var tPoseClip: MotionClip {
        let positions = OdoroSkeletonDefinition.jointNames.map { jointName in
            tPose.worldPositions[jointName] ?? SIMD3<Float>(0, -10, 0)
        }
        let rotations = OdoroSkeletonDefinition.jointNames.map { jointName in
            tPose.worldRotations[jointName].map(MotionJointRotation.init)
        }

        return MotionClip(frames: [
            MotionFrame(time: 0, jointPositions: positions, jointRotations: rotations),
            MotionFrame(time: 1.0 / 30.0, jointPositions: positions, jointRotations: rotations),
        ])
    }

    private let skeletonDefinition = ARSkeletonDefinition.defaultBody3D

    init() {
        let skeleton = ARSkeletonDefinition.defaultBody3D
        let neutralModelTransforms = skeleton.neutralBodySkeleton3D?.jointModelTransforms ?? []

        var positions: [OdoroJointName: SIMD3<Float>] = [:]
        var rotations: [OdoroJointName: simd_quatf] = [:]

        for joint in OdoroJointName.allCases {
            let arkitName = Self.arkitJointName(for: joint)
            let index = skeleton.index(for: arkitName)
            guard index != NSNotFound, neutralModelTransforms.indices.contains(index) else { continue }
            let m = neutralModelTransforms[index]
            positions[joint] = SIMD3<Float>(m.columns.3.x, m.columns.3.y, m.columns.3.z)
            rotations[joint] = simd_quaternion(m)
        }

        Self.deriveMissingTorsoJoints(positions: &positions, rotations: &rotations)
        self.tPose = AvatarDrivePose(worldPositions: positions, worldRotations: rotations)
    }

    /// Extracts a drive pose from a motion frame.
    ///
    /// Dispatches to the canonical or ARKit path based on joint count.
    func pose(from frame: MotionFrame) -> AvatarDrivePose {
        frame.jointPositions.count == OdoroSkeletonDefinition.jointCount
            ? canonicalPose(from: frame)
            : arkitPose(from: frame)
    }

    // MARK: - ARKit ↔ canonical joint mapping

    /// Maps a canonical OdoroJointName to its corresponding ARKit body joint name.
    static func arkitJointName(for joint: OdoroJointName) -> ARSkeleton.JointName {
        switch joint {
        case .root:          return .root
        case .spine:         return ARSkeleton.JointName(rawValue: "spine_3_joint")
        case .chest:         return ARSkeleton.JointName(rawValue: "spine_7_joint")
        case .neck:          return ARSkeleton.JointName(rawValue: "neck_1_joint")
        case .head:          return .head
        case .leftShoulder:  return .leftShoulder
        case .rightShoulder: return .rightShoulder
        case .leftUpperArm:  return ARSkeleton.JointName(rawValue: "left_arm_joint")
        case .rightUpperArm: return ARSkeleton.JointName(rawValue: "right_arm_joint")
        case .leftElbow:     return ARSkeleton.JointName(rawValue: "left_forearm_joint")
        case .rightElbow:    return ARSkeleton.JointName(rawValue: "right_forearm_joint")
        case .leftWrist:     return .leftHand
        case .rightWrist:    return .rightHand
        case .leftHip:       return ARSkeleton.JointName(rawValue: "left_upLeg_joint")
        case .rightHip:      return ARSkeleton.JointName(rawValue: "right_upLeg_joint")
        case .leftKnee:      return ARSkeleton.JointName(rawValue: "left_leg_joint")
        case .rightKnee:     return ARSkeleton.JointName(rawValue: "right_leg_joint")
        case .leftAnkle, .leftFoot:   return .leftFoot
        case .rightAnkle, .rightFoot: return .rightFoot
        }
    }

    // MARK: - Private

    private func canonicalPose(from frame: MotionFrame) -> AvatarDrivePose {
        var positions: [OdoroJointName: SIMD3<Float>] = [:]
        var rotations: [OdoroJointName: simd_quatf] = [:]

        for joint in OdoroJointName.allCases {
            let index = OdoroSkeletonDefinition.index(of: joint)
            guard frame.jointPositions.indices.contains(index) else { continue }
            let pos = frame.jointPositions[index]
            guard pos.y > -5 else { continue }
            positions[joint] = pos

            if let frameRotations = frame.jointRotations,
               frameRotations.indices.contains(index),
               let rotation = frameRotations[index] {
                rotations[joint] = rotation.simdValue
            }
        }

        Self.deriveMissingTorsoJoints(positions: &positions, rotations: &rotations)
        return AvatarDrivePose(worldPositions: positions, worldRotations: rotations)
    }

    private func arkitPose(from frame: MotionFrame) -> AvatarDrivePose {
        var positions: [OdoroJointName: SIMD3<Float>] = [:]
        var rotations: [OdoroJointName: simd_quatf] = [:]

        for joint in OdoroJointName.allCases {
            let arkitName = Self.arkitJointName(for: joint)
            let index = skeletonDefinition.index(for: arkitName)
            guard index != NSNotFound, frame.jointPositions.indices.contains(index) else { continue }
            let pos = frame.jointPositions[index]
            guard pos.y > -5 else { continue }
            positions[joint] = pos

            if let frameRotations = frame.jointRotations,
               frameRotations.indices.contains(index),
               let rotation = frameRotations[index] {
                rotations[joint] = rotation.simdValue
            }
        }

        Self.deriveMissingTorsoJoints(positions: &positions, rotations: &rotations)
        return AvatarDrivePose(worldPositions: positions, worldRotations: rotations)
    }

    /// Fills missing torso joints by deriving them from nearby canonical body landmarks.
    private static func deriveMissingTorsoJoints(
        positions: inout [OdoroJointName: SIMD3<Float>],
        rotations: inout [OdoroJointName: simd_quatf]
    ) {
        let shoulderCenter = midpoint(positions[.leftShoulder], positions[.rightShoulder])

        if positions[.spine] == nil {
            positions[.spine] = interpolatedPosition(from: positions[.root], to: shoulderCenter, t: 0.35)
        }
        if positions[.chest] == nil {
            positions[.chest] = interpolatedPosition(from: positions[.root], to: shoulderCenter, t: 0.82)
        }
        if positions[.neck] == nil {
            positions[.neck] = interpolatedPosition(from: positions[.chest] ?? shoulderCenter, to: positions[.head], t: 0.45)
        }

        if rotations[.spine] == nil {
            rotations[.spine] = rotations[.root]
        }
        if rotations[.chest] == nil {
            rotations[.chest] = rotations[.spine] ?? rotations[.root]
        }
        if rotations[.neck] == nil {
            rotations[.neck] = rotations[.head]
        }
    }

    private static func midpoint(_ lhs: SIMD3<Float>?, _ rhs: SIMD3<Float>?) -> SIMD3<Float>? {
        guard let lhs, let rhs else {
            return nil
        }

        return (lhs + rhs) * 0.5
    }

    private static func interpolatedPosition(from start: SIMD3<Float>?, to end: SIMD3<Float>?, t: Float) -> SIMD3<Float>? {
        guard let start, let end else {
            return nil
        }

        return start + (end - start) * t
    }
}
