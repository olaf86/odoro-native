//
//  ARKitLiveCaptureFrameValidator.swift
//  Odoro
//

import ARKit
import Foundation
import simd

struct ARKitLiveCaptureFrameValidation: Sendable {
    let isValid: Bool
    let rejectionReason: String?

    nonisolated init(isValid: Bool, rejectionReason: String? = nil) {
        self.isValid = isValid
        self.rejectionReason = rejectionReason
    }
}

struct ARKitLiveCaptureFrameValidator: Sendable {
    struct Tuning: Sendable {
        let minimumValidJointCount: Int = 4
        let maximumBodySpan: Float = 3.2
        let maximumHipToHeadDistance: Float = 1.35
        let maximumShoulderWidth: Float = 1.1

        nonisolated init() {}
    }

    let qualityEvaluator: MotionFrameQualityEvaluator
    let tuning: Tuning

    private let skeletonDefinition = ARSkeletonDefinition.defaultBody3D

    nonisolated init(
        qualityEvaluator: MotionFrameQualityEvaluator = .init(),
        tuning: Tuning = .init()
    ) {
        self.qualityEvaluator = qualityEvaluator
        self.tuning = tuning
    }

    nonisolated func validate(_ frame: MotionFrame) -> ARKitLiveCaptureFrameValidation {
        let validPositions = frame.jointPositions.filter(qualityEvaluator.isValidStagePosition)
        guard validPositions.count >= tuning.minimumValidJointCount else {
            return ARKitLiveCaptureFrameValidation(
                isValid: false,
                rejectionReason: "valid joint count \(validPositions.count) below minimum \(tuning.minimumValidJointCount)"
            )
        }

        let span = qualityEvaluator.span(of: validPositions)
        let maximumSpan = max(span.x, max(span.y, span.z))
        guard maximumSpan <= tuning.maximumBodySpan else {
            return ARKitLiveCaptureFrameValidation(
                isValid: false,
                rejectionReason: "body span \(maximumSpan) exceeds \(tuning.maximumBodySpan)"
            )
        }

        if let hipToHeadDistance = distance(between: .root, and: .head, in: frame),
           hipToHeadDistance > tuning.maximumHipToHeadDistance {
            return ARKitLiveCaptureFrameValidation(
                isValid: false,
                rejectionReason: "hip-head distance \(hipToHeadDistance) exceeds \(tuning.maximumHipToHeadDistance)"
            )
        }

        if let shoulderWidth = distance(between: .leftShoulder, and: .rightShoulder, in: frame),
           shoulderWidth > tuning.maximumShoulderWidth {
            return ARKitLiveCaptureFrameValidation(
                isValid: false,
                rejectionReason: "shoulder width \(shoulderWidth) exceeds \(tuning.maximumShoulderWidth)"
            )
        }

        return ARKitLiveCaptureFrameValidation(isValid: true)
    }

    private nonisolated func distance(
        between lhs: ARSkeleton.JointName,
        and rhs: ARSkeleton.JointName,
        in frame: MotionFrame
    ) -> Float? {
        guard
            let lhsPosition = position(for: lhs, in: frame),
            let rhsPosition = position(for: rhs, in: frame)
        else {
            return nil
        }

        return simd_distance(lhsPosition, rhsPosition)
    }

    private nonisolated func position(
        for jointName: ARSkeleton.JointName,
        in frame: MotionFrame
    ) -> SIMD3<Float>? {
        let index = skeletonDefinition.index(for: jointName)
        guard index != NSNotFound, frame.jointPositions.indices.contains(index) else {
            return nil
        }

        let position = frame.jointPositions[index]
        guard qualityEvaluator.isValidStagePosition(position) else {
            return nil
        }

        return position
    }
}
