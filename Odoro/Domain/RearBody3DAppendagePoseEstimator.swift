//
//  RearBody3DAppendagePoseEstimator.swift
//  Odoro
//

import Foundation
import simd

struct AppendagePose: Codable, Sendable, Equatable {
    let pivot: SIMD3<Float>
    let forward: SIMD3<Float>
    let up: SIMD3<Float>
    let confidence: Float

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.pivot == rhs.pivot
            && lhs.forward == rhs.forward
            && lhs.up == rhs.up
            && lhs.confidence == rhs.confidence
    }
}

struct FootPoses: Codable, Sendable, Equatable {
    let left: AppendagePose?
    let right: AppendagePose?
    let leftContactWeight: Float
    let rightContactWeight: Float

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.left == rhs.left
            && lhs.right == rhs.right
            && lhs.leftContactWeight == rhs.leftContactWeight
            && lhs.rightContactWeight == rhs.rightContactWeight
    }
}

struct HandPoses: Codable, Sendable, Equatable {
    let left: AppendagePose?
    let right: AppendagePose?

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.left == rhs.left && lhs.right == rhs.right
    }
}

struct MotionFrameAppendagePoses: Codable, Sendable, Equatable {
    let time: TimeInterval
    let feet: FootPoses
    let hands: HandPoses

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.time == rhs.time
            && lhs.feet == rhs.feet
            && lhs.hands == rhs.hands
    }
}

struct MotionClipAppendagePoses: Codable, Sendable, Equatable {
    let frames: [MotionFrameAppendagePoses]

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.frames == rhs.frames
    }
}

struct RearBody3DAppendagePoseEstimator: Sendable {
    struct Tuning: Sendable {
        let minimumDirectionLength: Float = 0.0001
        let footContactHeightTolerance: Float = 0.06
        let footContactSpeedTolerance: Float = 0.18
        let minimumRotationForwardBodyAlignment: Float = 0.45
        let footRotationInfluence: Float = 0.18
        let footForwardPreviousWeightBase: Float = 0.42
        let footForwardPreviousWeightContactScale: Float = 0.38
        let minimumFinalBodyForwardAlignment: Float = 0.18
        let highConfidence: Float = 0.85
        let mediumConfidence: Float = 0.55
        let lowConfidence: Float = 0.25

        nonisolated init() {}
    }

    let tuning: Tuning

    nonisolated init(tuning: Tuning = .init()) {
        self.tuning = tuning
    }

    nonisolated func estimatePoses(for clip: MotionClip) -> MotionClipAppendagePoses {
        var previousFootPoses = Array<AppendagePose?>(repeating: nil, count: 2)
        var inferredFrames: [MotionFrameAppendagePoses] = []
        inferredFrames.reserveCapacity(clip.frames.count)

        for (index, frame) in clip.frames.enumerated() {
            let inferredFrame = inferFrame(
                frame,
                at: index,
                in: clip.frames,
                previousFootPoses: previousFootPoses
            )
            inferredFrames.append(inferredFrame)

            if let left = inferredFrame.feet.left {
                previousFootPoses[BodySide.left.storageIndex] = left
            }
            if let right = inferredFrame.feet.right {
                previousFootPoses[BodySide.right.storageIndex] = right
            }
        }

        return MotionClipAppendagePoses(frames: inferredFrames)
    }

    nonisolated private func inferFrame(
        _ frame: MotionFrame,
        at index: Int,
        in frames: [MotionFrame],
        previousFootPoses: [AppendagePose?]
    ) -> MotionFrameAppendagePoses {
        guard frame.jointPositions.count == OdoroSkeletonDefinition.jointCount else {
            return MotionFrameAppendagePoses(
                time: frame.time,
                feet: FootPoses(left: nil, right: nil, leftContactWeight: 0, rightContactWeight: 0),
                hands: HandPoses(left: nil, right: nil)
            )
        }

        let bodyForwardHint = self.bodyForwardHint(in: frame)
        let leftContactWeight = footContactWeight(side: .left, frameIndex: index, frames: frames)
        let rightContactWeight = footContactWeight(side: .right, frameIndex: index, frames: frames)
        let leftFoot = inferFootPose(
            side: .left,
            in: frame,
            bodyForwardHint: bodyForwardHint,
            contactWeight: leftContactWeight,
            previousPose: previousFootPoses[BodySide.left.storageIndex]
        )
        let rightFoot = inferFootPose(
            side: .right,
            in: frame,
            bodyForwardHint: bodyForwardHint,
            contactWeight: rightContactWeight,
            previousPose: previousFootPoses[BodySide.right.storageIndex]
        )
        let leftHand = inferHandPose(side: .left, in: frame, bodyForwardHint: bodyForwardHint)
        let rightHand = inferHandPose(side: .right, in: frame, bodyForwardHint: bodyForwardHint)

        return MotionFrameAppendagePoses(
            time: frame.time,
            feet: FootPoses(
                left: leftFoot,
                right: rightFoot,
                leftContactWeight: leftContactWeight,
                rightContactWeight: rightContactWeight
            ),
            hands: HandPoses(left: leftHand, right: rightHand)
        )
    }

    nonisolated private func inferFootPose(
        side: BodySide,
        in frame: MotionFrame,
        bodyForwardHint: SIMD3<Float>?,
        contactWeight: Float,
        previousPose: AppendagePose?
    ) -> AppendagePose? {
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
        if let bodyForward {
            if let rotationForward {
                var alignedRotationForward = rotationForward
                if simd_dot(alignedRotationForward, bodyForward) < 0 {
                    alignedRotationForward *= -1
                }

                if simd_dot(alignedRotationForward, bodyForward) >= tuning.minimumRotationForwardBodyAlignment {
                    resolvedForward = normalizedOrNil(
                        bodyForward * (1 - tuning.footRotationInfluence)
                            + alignedRotationForward * tuning.footRotationInfluence
                    )
                } else {
                    resolvedForward = bodyForward
                }
            } else {
                resolvedForward = bodyForward
            }
        } else {
            resolvedForward = rotationForward
        }

        let baseForward = resolvedForward ?? orthogonalFallbackDirection(to: up)
        let stabilizedForward = stabilizedFootForward(
            baseForward,
            previousForward: previousPose?.forward,
            up: up,
            contactWeight: contactWeight
        ) ?? baseForward
        let forward = correctedFootForward(
            stabilizedForward,
            bodyForward: bodyForward,
            up: up
        ) ?? stabilizedForward
        let confidenceBase: Float
        if bodyForward != nil {
            confidenceBase = tuning.highConfidence
        } else if rotationForward != nil {
            confidenceBase = tuning.highConfidence
        } else {
            confidenceBase = tuning.lowConfidence
        }

        return AppendagePose(
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
    ) -> AppendagePose? {
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

        return AppendagePose(
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
        guard let bodyRight = bodyRightHint(in: frame) else {
            return nil
        }

        let up = SIMD3<Float>(0, 1, 0)
        guard var forward = normalizedOrNil(simd_cross(bodyRight, up)) else {
            return nil
        }

        if let noseForward = noseForwardHint(in: frame),
           simd_dot(forward, noseForward) < 0 {
            forward *= -1
        }

        return forward
    }

    nonisolated private func bodyRightHint(in frame: MotionFrame) -> SIMD3<Float>? {
        let candidates = [
            jointDirection(from: .leftShoulder, to: .rightShoulder, in: frame),
            jointDirection(from: .leftHip, to: .rightHip, in: frame),
        ].compactMap { $0 }

        guard !candidates.isEmpty else {
            return nil
        }

        return normalizedOrNil(candidates.reduce(.zero, +))
    }

    nonisolated private func noseForwardHint(in frame: MotionFrame) -> SIMD3<Float>? {
        guard
            let root = canonicalPosition(for: .root, in: frame),
            let nose = canonicalPosition(for: .nose, in: frame) ?? canonicalPosition(for: .head, in: frame)
        else {
            return nil
        }

        let horizontal = SIMD3<Float>(nose.x - root.x, 0, nose.z - root.z)
        return normalizedOrNil(horizontal)
    }

    nonisolated private func jointDirection(
        from startJoint: OdoroJointName,
        to endJoint: OdoroJointName,
        in frame: MotionFrame
    ) -> SIMD3<Float>? {
        guard
            let start = canonicalPosition(for: startJoint, in: frame),
            let end = canonicalPosition(for: endJoint, in: frame)
        else {
            return nil
        }

        return normalizedOrNil(end - start)
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

    nonisolated private func stabilizedFootForward(
        _ currentForward: SIMD3<Float>,
        previousForward: SIMD3<Float>?,
        up: SIMD3<Float>,
        contactWeight: Float
    ) -> SIMD3<Float>? {
        guard let previousForward = previousForward.flatMap({ projectedDirection($0, planeNormal: up) }) else {
            return currentForward
        }

        var alignedCurrentForward = currentForward
        if simd_dot(alignedCurrentForward, previousForward) < 0 {
            alignedCurrentForward *= -1
        }

        let previousWeight = min(
            0.9,
            tuning.footForwardPreviousWeightBase + contactWeight * tuning.footForwardPreviousWeightContactScale
        )
        return normalizedOrNil(
            previousForward * previousWeight
                + alignedCurrentForward * (1 - previousWeight)
        )
    }

    nonisolated private func correctedFootForward(
        _ currentForward: SIMD3<Float>,
        bodyForward: SIMD3<Float>?,
        up: SIMD3<Float>
    ) -> SIMD3<Float>? {
        guard let bodyForward else {
            return currentForward
        }

        let projectedBodyForward = projectedDirection(bodyForward, planeNormal: up) ?? bodyForward
        let alignment = simd_dot(currentForward, projectedBodyForward)
        guard alignment < tuning.minimumFinalBodyForwardAlignment else {
            return currentForward
        }

        let bodyBlend = max(0.55, 1 - max(alignment, -1) * 0.35)
        return normalizedOrNil(
            currentForward * (1 - bodyBlend)
                + projectedBodyForward * bodyBlend
        )
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

    nonisolated var storageIndex: Int {
        switch self {
        case .left:
            0
        case .right:
            1
        }
    }

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
