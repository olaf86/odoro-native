//
//  MockMotionSource.swift
//  Odoro
//

import Foundation
import ARKit
import simd

final class MockMotionSource: MotionSource {
    private static let upperArmInterpolation: Float = 0.35

    var captureMode: CaptureMode { .mock }
    var onFrame: ((MotionFrame) -> Void)?
    var onStatusTextChange: ((String) -> Void)?

    let isSupported = true

    private let skeletonDefinition = ARSkeletonDefinition.defaultBody3D
    private let neutralJointPositions: [SIMD3<Float>] = {
        let neutral = ARSkeletonDefinition.defaultBody3D.neutralBodySkeleton3D?.jointModelTransforms ?? []
        return neutral.map { transform in
            let translation = transform.columns.3
            return SIMD3<Float>(translation.x, translation.y, translation.z)
        }
    }()
    private var timer: Timer?
    private var startedAt: Date?
    private let frameInterval: TimeInterval = 1 / 30

    func activate(for activity: MotionSourceActivity) {
        guard timer == nil else { return }

        startedAt = Date()
        onStatusTextChange?(L10n.statusMockGenerating)

        timer = Timer.scheduledTimer(
            timeInterval: frameInterval,
            target: self,
            selector: #selector(handleTimer),
            userInfo: nil,
            repeats: true
        )
    }

    func deactivate() {
        timer?.invalidate()
        timer = nil
        startedAt = nil
    }

    @objc private func handleTimer() {
        guard let startedAt else { return }

        let elapsed = Date().timeIntervalSince(startedAt)
        onFrame?(makeFrame(at: elapsed))
    }

    private func makeFrame(at time: TimeInterval) -> MotionFrame {
        let rhythm = Float(time)
        let step = sin(rhythm * 2.2)
        let sway = sin(rhythm * 1.4)
        let armSwing = sin(rhythm * 3.1)
        let bounce = max(0, sin(rhythm * 4.4)) * 0.08

        let root = SIMD3<Float>(sway * 0.18, 0.95 + bounce, step * 0.08)
        let head = root + SIMD3<Float>(0, 0.62, 0)
        let neck = root + SIMD3<Float>(0, 0.47, 0)
        let leftShoulder = neck + SIMD3<Float>(-0.18, 0.03, 0)
        let rightShoulder = neck + SIMD3<Float>(0.18, 0.03, 0)
        let leftElbow = leftShoulder + SIMD3<Float>(-0.20, 0.10 + armSwing * 0.12, 0.04)
        let rightElbow = rightShoulder + SIMD3<Float>(0.20, 0.10 - armSwing * 0.12, 0.04)
        let leftHand = leftElbow + SIMD3<Float>(-0.16, -0.08 + armSwing * 0.10, 0)
        let rightHand = rightElbow + SIMD3<Float>(0.16, -0.08 - armSwing * 0.10, 0)
        let leftUpperArm = Self.interpolatedPosition(from: leftShoulder, to: leftElbow, t: Self.upperArmInterpolation)
        let rightUpperArm = Self.interpolatedPosition(from: rightShoulder, to: rightElbow, t: Self.upperArmInterpolation)
        let leftHip = root + SIMD3<Float>(-0.12, -0.02, 0)
        let rightHip = root + SIMD3<Float>(0.12, -0.02, 0)
        let leftKnee = leftHip + SIMD3<Float>(-0.03, -0.38 + max(0, step) * 0.08, 0.06)
        let rightKnee = rightHip + SIMD3<Float>(0.03, -0.38 + max(0, -step) * 0.08, -0.06)
        let leftFoot = leftKnee + SIMD3<Float>(0, -0.38, 0.05 + max(0, step) * 0.10)
        let rightFoot = rightKnee + SIMD3<Float>(0, -0.38, 0.05 + max(0, -step) * 0.10)

        var joints = neutralJointPositions

        if joints.count != skeletonDefinition.jointNames.count {
            joints = Array(repeating: SIMD3<Float>(0, -10, 0), count: skeletonDefinition.jointNames.count)
        }

        setJoint(.root, to: root, in: &joints)
        setJoint(named: "hips_joint", to: root, in: &joints)
        setJoint(named: "spine_1_joint", to: root + SIMD3<Float>(0, 0.08, 0), in: &joints)
        setJoint(named: "spine_2_joint", to: root + SIMD3<Float>(0, 0.16, 0), in: &joints)
        setJoint(named: "spine_3_joint", to: root + SIMD3<Float>(0, 0.24, 0), in: &joints)
        setJoint(named: "spine_4_joint", to: root + SIMD3<Float>(0, 0.30, 0), in: &joints)
        setJoint(named: "spine_5_joint", to: root + SIMD3<Float>(0, 0.36, 0), in: &joints)
        setJoint(named: "spine_6_joint", to: root + SIMD3<Float>(0, 0.41, 0), in: &joints)
        setJoint(named: "spine_7_joint", to: neck + SIMD3<Float>(0, -0.03, 0), in: &joints)

        setJoint(named: "neck_1_joint", to: neck + SIMD3<Float>(0, -0.02, 0), in: &joints)
        setJoint(named: "neck_2_joint", to: neck + SIMD3<Float>(0, 0.02, 0), in: &joints)
        setJoint(named: "neck_3_joint", to: neck + SIMD3<Float>(0, 0.07, 0), in: &joints)
        setJoint(named: "neck_4_joint", to: neck + SIMD3<Float>(0, 0.12, 0), in: &joints)
        setJoint(.head, to: head, in: &joints)

        setJoint(.leftShoulder, to: leftShoulder, in: &joints)
        setJoint(named: "left_shoulder_1_joint", to: leftShoulder, in: &joints)
        setJoint(named: "left_arm_joint", to: leftUpperArm, in: &joints)
        setJoint(named: "left_forearm_joint", to: leftElbow, in: &joints)
        setJoint(.leftHand, to: leftHand, in: &joints)
        setFingerChain(prefix: "left_hand", hand: leftHand, spread: 1, in: &joints)

        setJoint(.rightShoulder, to: rightShoulder, in: &joints)
        setJoint(named: "right_shoulder_1_joint", to: rightShoulder, in: &joints)
        setJoint(named: "right_arm_joint", to: rightUpperArm, in: &joints)
        setJoint(named: "right_forearm_joint", to: rightElbow, in: &joints)
        setJoint(.rightHand, to: rightHand, in: &joints)
        setFingerChain(prefix: "right_hand", hand: rightHand, spread: -1, in: &joints)

        setJoint(named: "left_upLeg_joint", to: leftHip, in: &joints)
        setJoint(named: "left_leg_joint", to: leftKnee, in: &joints)
        setJoint(.leftFoot, to: leftFoot, in: &joints)
        setJoint(named: "left_toes_joint", to: leftFoot + SIMD3<Float>(0, 0, 0.08), in: &joints)
        setJoint(named: "left_toesEnd_joint", to: leftFoot + SIMD3<Float>(0, 0, 0.14), in: &joints)

        setJoint(named: "right_upLeg_joint", to: rightHip, in: &joints)
        setJoint(named: "right_leg_joint", to: rightKnee, in: &joints)
        setJoint(.rightFoot, to: rightFoot, in: &joints)
        setJoint(named: "right_toes_joint", to: rightFoot + SIMD3<Float>(0, 0, 0.08), in: &joints)
        setJoint(named: "right_toesEnd_joint", to: rightFoot + SIMD3<Float>(0, 0, 0.14), in: &joints)

        return MotionFrame(time: time, jointPositions: joints)
    }

    private func setJoint(_ jointName: ARSkeleton.JointName, to position: SIMD3<Float>, in joints: inout [SIMD3<Float>]) {
        let index = skeletonDefinition.index(for: jointName)
        guard index != NSNotFound, joints.indices.contains(index) else {
            return
        }
        joints[index] = position
    }

    private func setJoint(named rawValue: String, to position: SIMD3<Float>, in joints: inout [SIMD3<Float>]) {
        setJoint(ARSkeleton.JointName(rawValue: rawValue), to: position, in: &joints)
    }

    private func setFingerChain(prefix: String, hand: SIMD3<Float>, spread: Float, in joints: inout [SIMD3<Float>]) {
        let fingerOffsets: [(String, SIMD3<Float>)] = [
            ("ThumbStart_joint", SIMD3<Float>(0.02 * spread, 0, 0.01)),
            ("Thumb_1_joint", SIMD3<Float>(0.04 * spread, 0.01, 0.02)),
            ("Thumb_2_joint", SIMD3<Float>(0.06 * spread, 0.01, 0.03)),
            ("ThumbEnd_joint", SIMD3<Float>(0.08 * spread, 0.01, 0.04)),
            ("IndexStart_joint", SIMD3<Float>(0.01 * spread, 0, 0.03)),
            ("Index_1_joint", SIMD3<Float>(0.01 * spread, 0, 0.07)),
            ("Index_2_joint", SIMD3<Float>(0.01 * spread, 0, 0.11)),
            ("Index_3_joint", SIMD3<Float>(0.01 * spread, 0, 0.15)),
            ("IndexEnd_joint", SIMD3<Float>(0.01 * spread, 0, 0.18)),
            ("MidStart_joint", SIMD3<Float>(0, 0, 0.03)),
            ("Mid_1_joint", SIMD3<Float>(0, 0, 0.08)),
            ("Mid_2_joint", SIMD3<Float>(0, 0, 0.13)),
            ("Mid_3_joint", SIMD3<Float>(0, 0, 0.18)),
            ("MidEnd_joint", SIMD3<Float>(0, 0, 0.22)),
            ("RingStart_joint", SIMD3<Float>(-0.01 * spread, 0, 0.03)),
            ("Ring_1_joint", SIMD3<Float>(-0.01 * spread, 0, 0.07)),
            ("Ring_2_joint", SIMD3<Float>(-0.01 * spread, 0, 0.11)),
            ("Ring_3_joint", SIMD3<Float>(-0.01 * spread, 0, 0.15)),
            ("RingEnd_joint", SIMD3<Float>(-0.01 * spread, 0, 0.18)),
            ("PinkyStart_joint", SIMD3<Float>(-0.02 * spread, 0, 0.03)),
            ("Pinky_1_joint", SIMD3<Float>(-0.02 * spread, 0, 0.06)),
            ("Pinky_2_joint", SIMD3<Float>(-0.02 * spread, 0, 0.09)),
            ("Pinky_3_joint", SIMD3<Float>(-0.02 * spread, 0, 0.12)),
            ("PinkyEnd_joint", SIMD3<Float>(-0.02 * spread, 0, 0.15)),
        ]

        setJoint(named: "\(prefix)_joint", to: hand, in: &joints)

        for (suffix, offset) in fingerOffsets {
            setJoint(named: "\(prefix)\(suffix)", to: hand + offset, in: &joints)
        }
    }

    private static func interpolatedPosition(from start: SIMD3<Float>, to end: SIMD3<Float>, t: Float) -> SIMD3<Float> {
        start + (end - start) * t
    }
}
