//
//  MockMotionSource.swift
//  Visco
//

import Foundation
import simd

final class MockMotionSource: MotionSource {
    var onFrame: ((MotionFrame) -> Void)?
    var onStatusTextChange: ((String) -> Void)?

    let isSupported = true

    private let jointCount = 91
    private var timer: Timer?
    private var startedAt: Date?
    private let frameInterval: TimeInterval = 1 / 30

    func start() {
        guard timer == nil else { return }

        startedAt = Date()
        onStatusTextChange?("MockMotionSource で疑似ダンスを生成しています")

        timer = Timer.scheduledTimer(
            timeInterval: frameInterval,
            target: self,
            selector: #selector(handleTimer),
            userInfo: nil,
            repeats: true
        )
    }

    func stop() {
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
        let leftHip = root + SIMD3<Float>(-0.12, -0.02, 0)
        let rightHip = root + SIMD3<Float>(0.12, -0.02, 0)
        let leftKnee = leftHip + SIMD3<Float>(-0.03, -0.38 + max(0, step) * 0.08, 0.06)
        let rightKnee = rightHip + SIMD3<Float>(0.03, -0.38 + max(0, -step) * 0.08, -0.06)
        let leftFoot = leftKnee + SIMD3<Float>(0, -0.38, 0.05 + max(0, step) * 0.10)
        let rightFoot = rightKnee + SIMD3<Float>(0, -0.38, 0.05 + max(0, -step) * 0.10)

        let keyJoints: [SIMD3<Float>] = [
            root,
            neck,
            head,
            leftShoulder,
            leftElbow,
            leftHand,
            rightShoulder,
            rightElbow,
            rightHand,
            leftHip,
            leftKnee,
            leftFoot,
            rightHip,
            rightKnee,
            rightFoot,
        ]

        let filler = SIMD3<Float>(0, -10, 0)
        let remaining = max(0, jointCount - keyJoints.count)
        let joints = keyJoints + Array(repeating: filler, count: remaining)

        return MotionFrame(time: time, jointPositions: joints)
    }
}
