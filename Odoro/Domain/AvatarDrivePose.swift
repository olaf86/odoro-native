//
//  AvatarDrivePose.swift
//  Odoro

import simd

/// A source-skeleton-agnostic snapshot of a body pose in world space.
///
/// All positions and rotations are world-space, keyed by OdoroJointName, so that the
/// avatar retargeter never needs to know which capture backend produced the motion.
/// AvatarPoseSampler is responsible for converting a MotionFrame into this type.
struct AvatarDrivePose: Sendable {
    let worldPositions: [OdoroJointName: SIMD3<Float>]
    let worldRotations: [OdoroJointName: simd_quatf]

    static let empty = AvatarDrivePose(worldPositions: [:], worldRotations: [:])
}

extension AvatarDrivePose {
    func worldPosition(for joint: OdoroJointName?) -> SIMD3<Float>? {
        guard let joint else { return nil }
        return worldPositions[joint]
    }

    func worldRotation(for joint: OdoroJointName?) -> simd_quatf? {
        guard let joint else { return nil }
        return worldRotations[joint]
    }

    func worldPosition(for reference: AvatarRigJointReference?) -> SIMD3<Float>? {
        worldPosition(for: reference?.canonicalJoint)
    }

    func worldRotation(for reference: AvatarRigJointReference?) -> simd_quatf? {
        worldRotation(for: reference?.canonicalJoint)
    }
}
