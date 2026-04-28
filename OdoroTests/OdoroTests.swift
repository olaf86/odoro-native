//
//  OdoroTests.swift
//  OdoroTests
//
//  Created by Yuta Ogawa on 2026/04/07.
//

import ARKit
import Foundation
import RealityKit
import SwiftData
import Testing
@testable import Odoro

struct OdoroTests {
    @Test func recordingContextComputesBeatLengthFromBarsAndMeter() {
        let context = MotionRecordingContext(
            tempoSourceType: .metronome,
            audioAssetReference: nil,
            bpm: 96,
            timeSignatureNumerator: 3,
            timeSignatureDenominator: 4,
            targetBarCount: 2,
            countInBarCount: 1,
            notes: nil
        )

        #expect(context.beatLength == 6)
    }

    @Test func recordingContextNormalizesToFixedTwoBarCaptureLength() {
        let context = MotionRecordingContext(
            tempoSourceType: .metronome,
            audioAssetReference: nil,
            bpm: 120,
            timeSignatureNumerator: 3,
            timeSignatureDenominator: 4,
            targetBarCount: 6,
            countInBarCount: 1,
            notes: nil
        )

        let normalized = context.normalizedForFixedCaptureLength()

        #expect(normalized.targetBarCount == MotionRecordingContext.fixedCaptureBarCount)
        #expect(normalized.fixedCaptureBeatLength == 6)
        #expect(normalized.fixedCaptureDuration == 3)
    }

    @Test func motionClipNormalizationMovesOriginToFootLevelAndFirstFrameCenter() {
        let rotations: [MotionJointRotation?] = [
            MotionJointRotation(simd_quatf(angle: 0.25, axis: SIMD3<Float>(0, 1, 0))),
            MotionJointRotation(simd_quatf(angle: 0.5, axis: SIMD3<Float>(1, 0, 0))),
        ]
        let clip = MotionClip(
            frames: [
                MotionFrame(
                    time: 0,
                    jointPositions: [
                        SIMD3<Float>(1, 2, 3),
                        SIMD3<Float>(3, 4, 5),
                    ],
                    jointRotations: rotations
                ),
                MotionFrame(
                    time: 0.5,
                    jointPositions: [
                        SIMD3<Float>(2, 3, 4),
                        SIMD3<Float>(4, 5, 6),
                    ],
                    jointRotations: rotations
                ),
            ]
        )

        let normalized = clip.normalizedForStage()

        #expect(normalized.frames[0].jointPositions[0] == SIMD3<Float>(-1, 0, -1))
        #expect(normalized.frames[0].jointPositions[1] == SIMD3<Float>(1, 2, 1))
        #expect(normalized.frames[1].jointPositions[0] == SIMD3<Float>(0, 1, 0))
        #expect(normalized.estimatedFrameRate == 2.0)
        #expect(normalized.frames[0].jointRotations == rotations)
    }

    @Test func motionClipNormalizationIgnoresInvalidFloorOutliers() {
        let clip = MotionClip(
            frames: [
                MotionFrame(
                    time: 0,
                    jointPositions: [
                        SIMD3<Float>(-0.2, 1.0, 0),
                        SIMD3<Float>(0.2, 0.0, 0),
                        SIMD3<Float>(0, -10.0, 0),
                    ]
                ),
                MotionFrame(
                    time: 1.0 / 30.0,
                    jointPositions: [
                        SIMD3<Float>(-0.2, 1.0, 0),
                        SIMD3<Float>(0.2, 0.0, 0),
                        SIMD3<Float>(0, -10.0, 0),
                    ]
                ),
                MotionFrame(
                    time: 2.0 / 30.0,
                    jointPositions: [
                        SIMD3<Float>(-0.2, 1.0, 0),
                        SIMD3<Float>(0.2, 0.0, 0),
                        SIMD3<Float>(0, -10.0, 0),
                    ]
                ),
            ]
        )

        let normalized = clip.normalizedForStage()

        #expect(normalized.frames[0].jointPositions[0].y == 1.0)
        #expect(normalized.frames[0].jointPositions[1].y == 0.0)
        #expect(normalized.frames[0].jointPositions[2].y == -10.0)
    }

    @Test func stagePlaybackCameraUsesFiniteFrustumForStableDepthPrecision() {
        let camera = StagePlaybackRenderer.makeStageCameraComponent()

        #expect(camera.near == 0.1)
        #expect(camera.far == 20.0)
        #expect(camera.fieldOfViewInDegrees == 60.0)
    }

    @Test func motionClipRebasingMovesOriginWithoutChangingRotations() {
        let rotations: [MotionJointRotation?] = [
            MotionJointRotation(simd_quatf(angle: 0.15, axis: SIMD3<Float>(0, 1, 0))),
            MotionJointRotation(simd_quatf(angle: 0.35, axis: SIMD3<Float>(1, 0, 0))),
        ]
        let clip = MotionClip(
            frames: [
                MotionFrame(
                    time: 0,
                    jointPositions: [
                        SIMD3<Float>(1, 2, 3),
                        SIMD3<Float>(3, 4, 5),
                    ],
                    jointRotations: rotations
                )
            ]
        )

        let rebased = clip.rebasedForStage()

        #expect(rebased.frames[0].jointPositions[0] == SIMD3<Float>(-1, 0, -1))
        #expect(rebased.frames[0].jointPositions[1] == SIMD3<Float>(1, 2, 1))
        #expect(rebased.frames[0].jointRotations == rotations)
    }

    @Test func motionFrameQualityEvaluatorScoresSparseInvalidFrameAsLowQuality() {
        let evaluator = MotionFrameQualityEvaluator()
        let frame = MotionFrame(
            time: 0,
            jointPositions: [
                SIMD3<Float>(0, 1, 0),
                SIMD3<Float>(0, -10, 0),
                SIMD3<Float>(.infinity, 0, 0),
            ]
        )

        let assessment = evaluator.assess(frame)

        #expect(assessment.score > 0)
        #expect(assessment.score < 0.2)
        #expect(assessment.validPositionMask == [true, false, false])
        #expect(assessment.jointScores.count == 3)
        #expect(assessment.jointScores[0] == assessment.score)
        #expect(assessment.jointScores[1] == 0)
        #expect(assessment.jointScores[2] == 0)
        #expect(assessment.robustCenter == SIMD3<Float>(0, 1, 0))
    }

    @Test func motionClipStageStabilizerEstimatesFloorWithoutInvalidOutliers() {
        let stabilizer = MotionClipStageStabilizer()
        let frames = [
            MotionFrame(
                time: 0,
                jointPositions: [
                    SIMD3<Float>(0, 1.1, 0),
                    SIMD3<Float>(0, 0.05, 0),
                    SIMD3<Float>(0, -10, 0),
                ]
            ),
            MotionFrame(
                time: 1.0 / 30.0,
                jointPositions: [
                    SIMD3<Float>(0, 1.15, 0),
                    SIMD3<Float>(0, 0.02, 0),
                    SIMD3<Float>(0, -10, 0),
                ]
            ),
            MotionFrame(
                time: 2.0 / 30.0,
                jointPositions: [
                    SIMD3<Float>(0, 1.2, 0),
                    SIMD3<Float>(0, 0.04, 0),
                    SIMD3<Float>(0, -10, 0),
                ]
            ),
        ]

        let floorHeight = stabilizer.estimatedFloorHeight(in: frames)

        #expect(floorHeight == 0.02)
    }

    @Test func arKitLiveCaptureFrameValidatorRejectsImplausiblyScaledBody() {
        let validator = ARKitLiveCaptureFrameValidator()
        let frame = Self.arKitFrame(
            time: 0,
            overrides: [
                .head: SIMD3<Float>(0, 3.2, 0),
                .leftShoulder: SIMD3<Float>(-1.0, 2.6, 0),
                .rightShoulder: SIMD3<Float>(1.0, 2.6, 0),
                .leftHand: SIMD3<Float>(-1.8, 2.0, 0.1),
                .rightHand: SIMD3<Float>(1.8, 2.0, 0.1),
                .leftFoot: SIMD3<Float>(-0.35, 0.0, 0.45),
                .rightFoot: SIMD3<Float>(0.35, 0.0, 0.45),
            ]
        )

        let validation = validator.validate(frame)

        #expect(!validation.isValid)
        #expect(validation.rejectionReason != nil)
    }

    @Test func motionClipStageStabilizerConstrainsCanonicalBoneLengthSpikes() {
        let stabilizer = MotionClipStageStabilizer()
        let baselineFrame = Self.canonicalFrame(
            time: 0,
            overrides: [
                .leftFoot: SIMD3<Float>(-0.12, 0.0, 0.18),
                .rightFoot: SIMD3<Float>(0.12, 0.0, 0.18),
            ]
        )
        let spikedFrame = Self.canonicalFrame(
            time: 1.0 / 30.0,
            overrides: [
                .leftFoot: SIMD3<Float>(0.62, 0.0, 1.18),
                .rightFoot: SIMD3<Float>(0.12, 0.0, 0.18),
            ]
        )
        let recoveredFrame = Self.canonicalFrame(
            time: 2.0 / 30.0,
            overrides: [
                .leftFoot: SIMD3<Float>(-0.12, 0.0, 0.18),
                .rightFoot: SIMD3<Float>(0.12, 0.0, 0.18),
            ]
        )

        let stabilized = stabilizer.stabilize(
            MotionClip(frames: [baselineFrame, spikedFrame, recoveredFrame])
        )

        let leftAnkleIndex = OdoroSkeletonDefinition.index(of: .leftAnkle)
        let leftFootIndex = OdoroSkeletonDefinition.index(of: .leftFoot)
        let referenceLength = simd_distance(
            baselineFrame.jointPositions[leftAnkleIndex],
            baselineFrame.jointPositions[leftFootIndex]
        )
        let rawSpikeLength = simd_distance(
            spikedFrame.jointPositions[leftAnkleIndex],
            spikedFrame.jointPositions[leftFootIndex]
        )
        let stabilizedSpikeLength = simd_distance(
            stabilized[1].jointPositions[leftAnkleIndex],
            stabilized[1].jointPositions[leftFootIndex]
        )

        #expect(abs(stabilizedSpikeLength - referenceLength) < abs(rawSpikeLength - referenceLength))
        #expect(stabilizedSpikeLength < rawSpikeLength)
    }

    @Test func motionClipStageStabilizerPinsCanonicalFootWhileContactLooksStable() {
        let stabilizer = MotionClipStageStabilizer()
        let pinnedX: Float = -0.12
        let clip = MotionClip(frames: [
            Self.canonicalFrame(
                time: 0,
                overrides: [
                    .leftFoot: SIMD3<Float>(pinnedX, 0.0, 0.18),
                    .rightFoot: SIMD3<Float>(0.12, 0.0, 0.18),
                ]
            ),
            Self.canonicalFrame(
                time: 1.0 / 30.0,
                overrides: [
                    .leftFoot: SIMD3<Float>(0.22, 0.01, 0.18),
                    .rightFoot: SIMD3<Float>(0.12, 0.0, 0.18),
                ]
            ),
            Self.canonicalFrame(
                time: 2.0 / 30.0,
                overrides: [
                    .leftFoot: SIMD3<Float>(0.26, 0.01, 0.18),
                    .rightFoot: SIMD3<Float>(0.12, 0.0, 0.18),
                ]
            ),
        ])

        let stabilized = stabilizer.stabilize(clip)
        let leftFootIndex = OdoroSkeletonDefinition.index(of: .leftFoot)
        let stabilizedFootX = stabilized[1].jointPositions[leftFootIndex].x

        #expect(abs(stabilizedFootX - pinnedX) < 0.08)
        #expect(abs(stabilizedFootX - pinnedX) < abs(clip.frames[1].jointPositions[leftFootIndex].x - pinnedX))
    }

    @Test func canonicalPoseMapperCanonicalizesClipFramesForPlayback() {
        let rawClip = MotionClip(frames: [
            MotionFrame(
                time: 0,
                jointPositions: [
                    SIMD3<Float>(0, 1, 0),
                    SIMD3<Float>(0, 1.6, 0),
                    SIMD3<Float>(-0.2, 1.4, 0),
                    SIMD3<Float>(0.2, 1.4, 0),
                    SIMD3<Float>(-0.4, 1.2, 0),
                    SIMD3<Float>(0.4, 1.2, 0),
                    SIMD3<Float>(-0.6, 1.0, 0),
                    SIMD3<Float>(0.6, 1.0, 0),
                    SIMD3<Float>(-0.1, 0.9, 0),
                    SIMD3<Float>(0.1, 0.9, 0),
                    SIMD3<Float>(-0.1, 0.5, 0.05),
                    SIMD3<Float>(0.1, 0.5, -0.05),
                    SIMD3<Float>(-0.1, 0.1, 0.12),
                    SIMD3<Float>(0.1, 0.1, 0.12),
                ]
            )
        ])

        let canonicalClip = OdoroCanonicalPoseMapper.canonicalizedClip(from: rawClip)

        #expect(canonicalClip.frameCount == 1)
        #expect(canonicalClip.frames[0].jointPositions.count == OdoroSkeletonDefinition.jointCount)
    }

    @Test func canonicalPoseMapperPlacesDerivedAnklesCloserToFootThanLegacyMidpoint() {
        let jointNames = arkitFixtureJointNames.map(ARSkeleton.JointName.init(rawValue:))
        let jointIndex: (ARSkeleton.JointName) -> Int = { name in
            jointNames.firstIndex(of: name) ?? NSNotFound
        }
        var positions = Array(
            repeating: SIMD3<Float>(0, -10, 0),
            count: jointNames.count
        )

        func setJoint(_ name: ARSkeleton.JointName, position: SIMD3<Float>) {
            let index = jointIndex(name)
            guard index != NSNotFound else { return }
            positions[index] = position
        }

        let leftKnee = SIMD3<Float>(-0.12, 0.47, 0.04)
        let leftFoot = SIMD3<Float>(-0.12, 0.08, 0.12)

        setJoint(ARSkeleton.JointName(rawValue: "left_leg_joint"), position: leftKnee)
        setJoint(.leftFoot, position: leftFoot)
        setJoint(ARSkeleton.JointName(rawValue: "left_foot_joint"), position: leftFoot)

        let mapped = OdoroCanonicalPoseMapper.map(
            frame: MotionFrame(time: 0, jointPositions: positions),
            jointIndex: jointIndex
        )

        let leftKneeIndex = OdoroSkeletonDefinition.index(of: .leftKnee)
        let leftAnkleIndex = OdoroSkeletonDefinition.index(of: .leftAnkle)
        let leftFootIndex = OdoroSkeletonDefinition.index(of: .leftFoot)

        let knee = mapped.positions[leftKneeIndex].simdValue
        let ankle = mapped.positions[leftAnkleIndex].simdValue
        let foot = mapped.positions[leftFootIndex].simdValue

        let legacyMidpointDistance = simd_distance((knee + foot) * 0.5, foot)
        let derivedDistance = simd_distance(ankle, foot)
        let lowerLegLength = simd_distance(knee, foot)

        #expect(mapped.statuses[leftAnkleIndex] == .derived)
        #expect(derivedDistance < legacyMidpointDistance)
        #expect(abs((derivedDistance / lowerLegLength) - 0.08) < 0.02)
    }

    @Test func canonicalPoseMapperMapsElbowsFromForearmJoints() {
        let jointNames: [ARSkeleton.JointName] = [
            .root,
            .head,
            ARSkeleton.JointName(rawValue: "nose_joint"),
            .leftShoulder,
            .rightShoulder,
            ARSkeleton.JointName(rawValue: "left_arm_joint"),
            ARSkeleton.JointName(rawValue: "right_arm_joint"),
            ARSkeleton.JointName(rawValue: "left_forearm_joint"),
            ARSkeleton.JointName(rawValue: "right_forearm_joint"),
            .leftHand,
            .rightHand,
            ARSkeleton.JointName(rawValue: "left_upLeg_joint"),
            ARSkeleton.JointName(rawValue: "right_upLeg_joint"),
            ARSkeleton.JointName(rawValue: "left_leg_joint"),
            ARSkeleton.JointName(rawValue: "right_leg_joint"),
            .leftFoot,
            .rightFoot,
        ]
        let jointIndex: (ARSkeleton.JointName) -> Int = { name in
            jointNames.firstIndex(of: name) ?? NSNotFound
        }
        let leftArm = SIMD3<Float>(-0.28, 1.38, 0)
        let leftForearm = SIMD3<Float>(-0.48, 1.18, 0.02)
        let leftHand = SIMD3<Float>(-0.66, 0.98, 0.03)
        let rightArm = SIMD3<Float>(0.28, 1.38, 0)
        let rightForearm = SIMD3<Float>(0.48, 1.18, 0.02)
        let rightHand = SIMD3<Float>(0.66, 0.98, 0.03)
        let frame = MotionFrame(
            time: 0,
            jointPositions: [
                SIMD3<Float>(0, 1, 0),
                SIMD3<Float>(0, 1.6, 0),
                SIMD3<Float>(0, 1.68, 0.04),
                SIMD3<Float>(-0.2, 1.4, 0),
                SIMD3<Float>(0.2, 1.4, 0),
                leftArm,
                rightArm,
                leftForearm,
                rightForearm,
                leftHand,
                rightHand,
                SIMD3<Float>(-0.1, 0.9, 0),
                SIMD3<Float>(0.1, 0.9, 0),
                SIMD3<Float>(-0.1, 0.5, 0.05),
                SIMD3<Float>(0.1, 0.5, -0.05),
                SIMD3<Float>(-0.1, 0.1, 0.12),
                SIMD3<Float>(0.1, 0.1, 0.12),
            ]
        )

        let mapped = OdoroCanonicalPoseMapper.map(frame: frame, jointIndex: jointIndex)

        #expect(mapped.positions[OdoroSkeletonDefinition.index(of: .leftUpperArm)].simdValue == leftArm)
        #expect(mapped.positions[OdoroSkeletonDefinition.index(of: .rightUpperArm)].simdValue == rightArm)
        #expect(mapped.positions[OdoroSkeletonDefinition.index(of: .leftElbow)].simdValue == leftForearm)
        #expect(mapped.positions[OdoroSkeletonDefinition.index(of: .rightElbow)].simdValue == rightForearm)
        #expect(mapped.positions[OdoroSkeletonDefinition.index(of: .leftWrist)].simdValue == leftHand)
        #expect(mapped.positions[OdoroSkeletonDefinition.index(of: .rightWrist)].simdValue == rightHand)
    }

    @Test func rearBodyInferenceProducesFootPoseForCanonicalClip() throws {
        let clip = MotionClip(frames: [
            Self.canonicalFrame(time: 0),
            Self.canonicalFrame(time: 1.0 / 30.0),
        ])

        let inference = RearBody3DAppendagePoseEstimator().estimatePoses(for: clip)
        let leftFoot = try #require(inference.frames.first?.feet.left)

        #expect(inference.frames.count == clip.frames.count)
        #expect(leftFoot.pivot == clip.frames[0].jointPositions[OdoroSkeletonDefinition.index(of: .leftFoot)])
        #expect(leftFoot.forward.z > 0.5)
        #expect(leftFoot.confidence >= 0.55)
        #expect((inference.frames.first?.feet.leftContactWeight ?? 0) > 0.5)
    }

    @Test func rearBodyInferenceLeavesUnsupportedSkeletonEmpty() {
        let clip = MotionClip(frames: [
            MotionFrame(
                time: 0,
                jointPositions: [
                    SIMD3<Float>(0, 1, 0),
                    SIMD3<Float>(0, 0, 0),
                ]
            )
        ])

        let inference = RearBody3DAppendagePoseEstimator().estimatePoses(for: clip)

        #expect(inference.frames.count == 1)
        #expect(inference.frames[0].feet.left == nil)
        #expect(inference.frames[0].feet.right == nil)
        #expect(inference.frames[0].hands.left == nil)
        #expect(inference.frames[0].hands.right == nil)
    }

    @Test func stagePreparedPlaybackBuilderCachesRearBodyInferenceOnPreparedVariants() {
        let sourceClip = MotionClip(frames: [
            MotionFrame(
                time: 0,
                jointPositions: Array(repeating: .zero, count: 2)
            ),
            MotionFrame(
                time: 1.0 / 30.0,
                jointPositions: Array(repeating: .zero, count: 2)
            ),
        ])
        let playbackClip = MotionClip(frames: [
            Self.canonicalFrame(time: 0),
            Self.canonicalFrame(time: 1.0 / 30.0),
        ])

        let prepared = StagePreparedPlaybackBuilder().prepare(
            sourceClip: sourceClip,
            playbackClip: playbackClip,
            captureMode: .rearBody3D
        )

        #expect(prepared.raw.appendagePoses == nil)
        #expect(prepared.canonical.clip != nil)
        #expect(prepared.canonical.appendagePoses?.frames.count == prepared.canonical.clip?.frames.count)
        #expect(prepared.stabilized.appendagePoses?.frames.count == prepared.stabilized.clip?.frames.count)
    }

    @Test func stagePreparedPlaybackBuilderSkipsInferenceOutsideRearBodyMode() {
        let playbackClip = MotionClip(frames: [
            Self.canonicalFrame(time: 0),
            Self.canonicalFrame(time: 1.0 / 30.0),
        ])

        let prepared = StagePreparedPlaybackBuilder().prepare(
            sourceClip: nil,
            playbackClip: playbackClip,
            captureMode: .importedVideo
        )

        #expect(prepared.canonical.appendagePoses == nil)
        #expect(prepared.stabilized.appendagePoses == nil)
    }

    @Test func stagePreparedPlaybackBuilderUsesStoredArtifactsWhenSourceClipIsUnavailable() throws {
        let playbackClip = MotionClip(frames: [
            Self.canonicalFrame(time: 0),
            Self.canonicalFrame(time: 1.0 / 30.0),
        ])
        let storedArtifacts = try #require(
            MotionPlaybackArtifactsBuilder().build(
                playbackClip: playbackClip,
                captureMode: .rearBody3D
            )
        )

        let prepared = StagePreparedPlaybackBuilder().prepare(
            sourceClip: nil,
            playbackClip: playbackClip,
            captureMode: .rearBody3D,
            playbackArtifacts: storedArtifacts
        )

        #expect(prepared.canonical.appendagePoses == storedArtifacts.stagePlayback?.canonical.appendagePoses)
        #expect(prepared.stabilized.appendagePoses == storedArtifacts.stagePlayback?.stabilized.appendagePoses)
    }

    @Test func motionPayloadRoundTripPreservesCanonicalClipWithoutRemapping() {
        let canonicalClip = MotionClip(frames: [
            Self.canonicalFrame(
                time: 0,
                overrides: [
                    .root: SIMD3<Float>(0.1, 1.05, 0.02),
                    .leftFoot: SIMD3<Float>(-0.14, 0.0, 0.2),
                ]
            )
        ])

        let payload = MotionPayload(
            clip: canonicalClip,
            clipIsCanonical: true,
            captureMode: .rearBody3D,
            recordingContext: .defaultMetronomeLoop,
            sourcePlatform: "iOS",
            sourceBackend: "arkit.bodyTracking"
        )

        let reloadedClip = payload.makeMotionClip()
        let leftFootIndex = OdoroSkeletonDefinition.index(of: .leftFoot)

        #expect(reloadedClip.frameCount == 1)
        #expect(reloadedClip.frames[0].jointPositions.count == OdoroSkeletonDefinition.jointCount)
        #expect(reloadedClip.frames[0].jointPositions[leftFootIndex] == canonicalClip.frames[0].jointPositions[leftFootIndex])
    }

    @Test func motionClipNormalizationDampensPositionSpikes() {
        let clip = MotionClip(
            frames: [
                MotionFrame(
                    time: 0,
                    jointPositions: [
                        SIMD3<Float>(0, 1, 0),
                        SIMD3<Float>(0.2, 1, 0),
                        SIMD3<Float>(0, 0, 0),
                    ]
                ),
                MotionFrame(
                    time: 1.0 / 30.0,
                    jointPositions: [
                        SIMD3<Float>(0.02, 1, 0),
                        SIMD3<Float>(4.0, 1, 0),
                        SIMD3<Float>(0.02, 0, 0),
                    ]
                ),
                MotionFrame(
                    time: 2.0 / 30.0,
                    jointPositions: [
                        SIMD3<Float>(0.04, 1, 0),
                        SIMD3<Float>(0.24, 1, 0),
                        SIMD3<Float>(0.04, 0, 0),
                    ]
                ),
            ]
        )

        let normalized = clip.normalizedForStage()
        let spikedJointX = normalized.frames[1].jointPositions[1].x

        #expect(spikedJointX < 1.2)
        #expect(spikedJointX > 0.2)
    }

    @Test func motionClipNormalizationDampensRotationSpikes() throws {
        let identity = MotionJointRotation(simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0)))
        let rotationSpike = MotionJointRotation(simd_quatf(angle: .pi, axis: SIMD3<Float>(0, 1, 0)))
        let positions = [
            SIMD3<Float>(0, 1, 0),
            SIMD3<Float>(0.2, 1, 0),
            SIMD3<Float>(0, 0, 0),
        ]
        let clip = MotionClip(
            frames: [
                MotionFrame(time: 0, jointPositions: positions, jointRotations: [identity]),
                MotionFrame(time: 1.0 / 30.0, jointPositions: positions, jointRotations: [rotationSpike]),
                MotionFrame(time: 2.0 / 30.0, jointPositions: positions, jointRotations: [identity]),
            ]
        )

        let normalized = clip.normalizedForStage()
        let smoothedSpike = try #require(normalized.frames[1].jointRotations?[0])
        let angle = Self.rotationAngle(smoothedSpike.simdValue)

        #expect(angle < 1.5)
    }

    @Test func canonicalPoseMapperReturnsCanonicalMissingSkeletonForUnsupportedInput() {
        let frame = MotionFrame(time: 0, jointPositions: [])

        let mapped = OdoroCanonicalPoseMapper.map(frame: frame)

        #expect(mapped.positions.count == OdoroSkeletonDefinition.jointCount)
        #expect(mapped.statuses.count == OdoroSkeletonDefinition.jointCount)
        #expect(mapped.rotations == nil)
        #expect(mapped.statuses.allSatisfy { $0 == .missing })
        #expect(mapped.positions.allSatisfy { $0.simdValue == .zero })
    }

    @Test func stageRendererTreatsAllNilRotationsAsUnusableForAvatarRigging() {
        #expect(StagePlaybackRenderer.hasUsableJointRotations(nil) == false)
        #expect(StagePlaybackRenderer.hasUsableJointRotations([]) == false)
        #expect(StagePlaybackRenderer.hasUsableJointRotations([nil, nil]) == false)
        #expect(StagePlaybackRenderer.hasUsableJointRotations([nil, MotionJointRotation(ix: 0, iy: 0, iz: 0, r: 1)]) == true)
    }

    @Test func robotRigProfileUsesUsdSkeletonJointPaths() {
        let profile = AvatarCatalog.robotRigProfile

        #expect(profile.rootBoneName == "root/hips_joint")
        #expect(profile.bindings.allSatisfy { $0.boneName.contains("/") })
        #expect(profile.bindings.contains { $0.boneName == "root/hips_joint/spine_1_joint/spine_2_joint" })
        #expect(profile.bindings.contains { $0.boneName == "root/hips_joint/left_upLeg_joint/left_leg_joint/left_foot_joint" })
        #expect(profile.bindings.contains { $0.boneName == "root/hips_joint/spine_1_joint/spine_2_joint/spine_3_joint/spine_4_joint/spine_5_joint/spine_6_joint/spine_7_joint/right_shoulder_1_joint/right_arm_joint/right_forearm_joint/right_hand_joint" })
        #expect(profile.bindings.first(where: { $0.boneName == profile.rootBoneName })?.translationMode == .direct)
        #expect(profile.bindings.filter { $0.boneName != profile.rootBoneName }.allSatisfy { $0.translationMode == .bindPose })
        #expect(profile.bindings.first(where: { $0.boneName.hasSuffix("/left_shoulder_1_joint") })?.weight == RobotRigTuning.shoulderRotationWeight)
        #expect(profile.bindings.first(where: { $0.boneName.hasSuffix("/right_shoulder_1_joint") })?.weight == RobotRigTuning.shoulderRotationWeight)
    }

    @Test func stageRendererBindPoseTranslationKeepsExistingJointOffset() {
        let baseTransform = Transform(
            scale: SIMD3<Float>(1.2, 1.2, 1.2),
            rotation: simd_quatf(angle: 0.05, axis: SIMD3<Float>(0, 1, 0)),
            translation: SIMD3<Float>(0, 0.42, 0.18)
        )
        let worldRotation = simd_quatf(angle: 0.4, axis: SIMD3<Float>(0, 0, 1))
        let parentWorldRotation = simd_quatf(angle: -0.2, axis: SIMD3<Float>(0, 1, 0))
        let localTransform = StagePlaybackRenderer.makeRigLocalTransform(
            preserving: baseTransform,
            worldRotation: worldRotation,
            worldPosition: SIMD3<Float>(1.0, 1.8, 0.3),
            parentWorldRotation: parentWorldRotation,
            parentWorldPosition: SIMD3<Float>(0.9, 1.0, 0.1),
            floorOffset: 0.977,
            translationMode: .bindPose,
            preservesBindPoseRotation: false,
            rotationWeight: 1
        )

        #expect(localTransform.translation == baseTransform.translation)
        #expect(localTransform.scale == baseTransform.scale)
        #expect(localTransform.rotation != baseTransform.rotation)
    }

    @Test func stageRendererBindPoseRotationPreservesBaseOrientationAtRest() {
        let baseTransform = Transform(
            scale: .one,
            rotation: simd_quatf(angle: .pi / 2, axis: SIMD3<Float>(1, 0, 0)),
            translation: SIMD3<Float>(0, 0.3, 0)
        )

        let localTransform = StagePlaybackRenderer.makeRigLocalTransform(
            preserving: baseTransform,
            worldRotation: simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0)),
            worldPosition: .zero,
            parentWorldRotation: nil,
            parentWorldPosition: nil,
            floorOffset: 0.977,
            translationMode: .bindPose,
            preservesBindPoseRotation: true,
            rotationWeight: 1
        )

        #expect(localTransform.rotation == baseTransform.rotation)
        #expect(localTransform.translation == baseTransform.translation)
    }

    @Test func stageRendererRotationWeightDampensAppliedLocalRotation() {
        let fullRotation = StagePlaybackRenderer.weightedRotation(
            simd_quatf(angle: .pi / 2, axis: SIMD3<Float>(0, 0, 1)),
            weight: 1
        )
        let dampedRotation = StagePlaybackRenderer.weightedRotation(
            simd_quatf(angle: .pi / 2, axis: SIMD3<Float>(0, 0, 1)),
            weight: RobotRigTuning.shoulderRotationWeight
        )

        #expect(Self.rotationAngle(dampedRotation) < Self.rotationAngle(fullRotation))
        #expect(Self.rotationAngle(dampedRotation) > 0)
    }

    @Test func stageRendererPreservesBindPoseRotationForTorsoHeadAndSharedCanonicalBindings() {
        #expect(
            StagePlaybackRenderer.shouldPreserveBindPoseRotation(
                for: AvatarBoneBinding(
                    boneName: "spine",
                    sourceJoint: .init(canonicalJoint: .root),
                    translationMode: .bindPose
                )
            )
        )
        #expect(
            StagePlaybackRenderer.shouldPreserveBindPoseRotation(
                for: AvatarBoneBinding(
                    boneName: "head",
                    sourceJoint: .init(canonicalJoint: .head),
                    translationMode: .bindPose
                )
            )
        )
        #expect(
            StagePlaybackRenderer.shouldPreserveBindPoseRotation(
                for: AvatarBoneBinding(
                    boneName: "left_hand",
                    sourceJoint: .init(canonicalJoint: .leftWrist, rawJointName: "left_hand_joint"),
                    parentSourceJoint: .init(canonicalJoint: .leftWrist, rawJointName: "left_forearm_joint"),
                    translationMode: .bindPose
                )
            )
        )
        #expect(
            !StagePlaybackRenderer.shouldPreserveBindPoseRotation(
                for: AvatarBoneBinding(
                    boneName: "left_arm",
                    sourceJoint: .init(canonicalJoint: .leftElbow),
                    translationMode: .bindPose
                )
            )
        )
        #expect(
            !StagePlaybackRenderer.shouldPreserveBindPoseRotation(
                for: AvatarBoneBinding(
                    boneName: "hips",
                    sourceJoint: .init(canonicalJoint: .root),
                    translationMode: .direct
                )
            )
        )
    }

    @Test func motionPayloadRoundTripPreservesMappedRotations() {
        let skeletonJointNames = arkitFixtureJointNames
        var positions = Array(
            repeating: SIMD3<Float>(0, -10, 0),
            count: skeletonJointNames.count
        )
        var rotations = Array<MotionJointRotation?>(
            repeating: nil,
            count: skeletonJointNames.count
        )

        func jointIndex(_ name: ARSkeleton.JointName) -> Int {
            skeletonJointNames.firstIndex(where: {
                $0 == name.rawValue
            }) ?? NSNotFound
        }

        func setJoint(_ name: ARSkeleton.JointName, position: SIMD3<Float>, rotation: simd_quatf) {
            let index = jointIndex(name)
            guard index != NSNotFound else { return }
            positions[index] = position
            rotations[index] = MotionJointRotation(rotation)
        }

        let rootRotation = simd_quatf(angle: 0.1, axis: SIMD3<Float>(0, 1, 0))
        let headRotation = simd_quatf(angle: 0.2, axis: SIMD3<Float>(1, 0, 0))
        let leftShoulderRotation = simd_quatf(angle: 0.3, axis: SIMD3<Float>(0, 0, 1))
        let rightShoulderRotation = simd_quatf(angle: -0.3, axis: SIMD3<Float>(0, 0, 1))
        let leftArmRotation = simd_quatf(angle: 0.15, axis: SIMD3<Float>(1, 0, 0))
        let rightArmRotation = simd_quatf(angle: -0.15, axis: SIMD3<Float>(1, 0, 0))
        let leftForearmRotation = simd_quatf(angle: 0.22, axis: SIMD3<Float>(0, 0, 1))
        let rightForearmRotation = simd_quatf(angle: -0.22, axis: SIMD3<Float>(0, 0, 1))
        let leftFootRotation = simd_quatf(angle: 0.4, axis: SIMD3<Float>(1, 1, 0))
        let rightFootRotation = simd_quatf(angle: -0.4, axis: SIMD3<Float>(1, 1, 0))

        setJoint(.root, position: SIMD3<Float>(0, 1, 0), rotation: rootRotation)
        setJoint(.head, position: SIMD3<Float>(0, 1.6, 0), rotation: headRotation)
        setJoint(.leftShoulder, position: SIMD3<Float>(-0.2, 1.4, 0), rotation: leftShoulderRotation)
        setJoint(.rightShoulder, position: SIMD3<Float>(0.2, 1.4, 0), rotation: rightShoulderRotation)
        setJoint(ARSkeleton.JointName(rawValue: "left_arm_joint"), position: SIMD3<Float>(-0.3, 1.3, 0), rotation: leftArmRotation)
        setJoint(ARSkeleton.JointName(rawValue: "right_arm_joint"), position: SIMD3<Float>(0.3, 1.3, 0), rotation: rightArmRotation)
        setJoint(ARSkeleton.JointName(rawValue: "left_forearm_joint"), position: SIMD3<Float>(-0.48, 1.16, 0), rotation: leftForearmRotation)
        setJoint(ARSkeleton.JointName(rawValue: "right_forearm_joint"), position: SIMD3<Float>(0.48, 1.16, 0), rotation: rightForearmRotation)
        setJoint(.leftHand, position: SIMD3<Float>(-0.6, 1.0, 0), rotation: simd_quatf(angle: 0.1, axis: SIMD3<Float>(0, 1, 1)))
        setJoint(.rightHand, position: SIMD3<Float>(0.6, 1.0, 0), rotation: simd_quatf(angle: -0.1, axis: SIMD3<Float>(0, 1, 1)))
        setJoint(ARSkeleton.JointName(rawValue: "left_upLeg_joint"), position: SIMD3<Float>(-0.1, 0.9, 0), rotation: simd_quatf(angle: 0.12, axis: SIMD3<Float>(1, 0, 1)))
        setJoint(ARSkeleton.JointName(rawValue: "right_upLeg_joint"), position: SIMD3<Float>(0.1, 0.9, 0), rotation: simd_quatf(angle: -0.12, axis: SIMD3<Float>(1, 0, 1)))
        setJoint(ARSkeleton.JointName(rawValue: "left_leg_joint"), position: SIMD3<Float>(-0.1, 0.5, 0.05), rotation: simd_quatf(angle: 0.18, axis: SIMD3<Float>(0, 1, 1)))
        setJoint(ARSkeleton.JointName(rawValue: "right_leg_joint"), position: SIMD3<Float>(0.1, 0.5, -0.05), rotation: simd_quatf(angle: -0.18, axis: SIMD3<Float>(0, 1, 1)))
        setJoint(.leftFoot, position: SIMD3<Float>(-0.1, 0.1, 0.12), rotation: leftFootRotation)
        setJoint(.rightFoot, position: SIMD3<Float>(0.1, 0.1, 0.12), rotation: rightFootRotation)

        let payload = MotionPayload(
            clip: MotionClip(frames: [
                MotionFrame(
                    time: 0,
                    jointPositions: positions,
                    jointRotations: rotations
                )
            ]),
            captureMode: .rearBody3D,
            recordingContext: .defaultMetronomeLoop,
            sourcePlatform: "iOS",
            sourceBackend: "arkit.bodyTracking",
            canonicalPoseMapper: { frame in
                OdoroCanonicalPoseMapper.map(frame: frame, jointIndex: jointIndex)
            }
        )

        let reloadedFrame = payload.makeMotionClip().frames[0]

        #expect(reloadedFrame.jointRotations?.count == OdoroSkeletonDefinition.jointCount)
        #expect(reloadedFrame.jointRotations?[OdoroSkeletonDefinition.index(of: .root)] == MotionJointRotation(rootRotation))
        #expect(reloadedFrame.jointRotations?[OdoroSkeletonDefinition.index(of: .nose)] == MotionJointRotation(headRotation))
        #expect(reloadedFrame.jointRotations?[OdoroSkeletonDefinition.index(of: .leftShoulder)] == MotionJointRotation(leftShoulderRotation))
        #expect(reloadedFrame.jointRotations?[OdoroSkeletonDefinition.index(of: .rightShoulder)] == MotionJointRotation(rightShoulderRotation))
        #expect(reloadedFrame.jointRotations?[OdoroSkeletonDefinition.index(of: .leftUpperArm)] == MotionJointRotation(leftArmRotation))
        #expect(reloadedFrame.jointRotations?[OdoroSkeletonDefinition.index(of: .rightUpperArm)] == MotionJointRotation(rightArmRotation))
        #expect(reloadedFrame.jointRotations?[OdoroSkeletonDefinition.index(of: .leftElbow)] == MotionJointRotation(leftForearmRotation))
        #expect(reloadedFrame.jointRotations?[OdoroSkeletonDefinition.index(of: .rightElbow)] == MotionJointRotation(rightForearmRotation))
        #expect(reloadedFrame.jointRotations?[OdoroSkeletonDefinition.index(of: .leftAnkle)] == MotionJointRotation(leftFootRotation))
        #expect(reloadedFrame.jointRotations?[OdoroSkeletonDefinition.index(of: .rightFoot)] == MotionJointRotation(rightFootRotation))
    }

    private var arkitFixtureJointNames: [String] {
        [
            ARSkeleton.JointName.root.rawValue,
            ARSkeleton.JointName.head.rawValue,
            ARSkeleton.JointName(rawValue: "nose_joint").rawValue,
            ARSkeleton.JointName.leftShoulder.rawValue,
            ARSkeleton.JointName.rightShoulder.rawValue,
            ARSkeleton.JointName(rawValue: "left_arm_joint").rawValue,
            ARSkeleton.JointName(rawValue: "right_arm_joint").rawValue,
            ARSkeleton.JointName(rawValue: "left_forearm_joint").rawValue,
            ARSkeleton.JointName(rawValue: "right_forearm_joint").rawValue,
            ARSkeleton.JointName.leftHand.rawValue,
            ARSkeleton.JointName.rightHand.rawValue,
            ARSkeleton.JointName(rawValue: "left_upLeg_joint").rawValue,
            ARSkeleton.JointName(rawValue: "right_upLeg_joint").rawValue,
            ARSkeleton.JointName(rawValue: "left_leg_joint").rawValue,
            ARSkeleton.JointName(rawValue: "right_leg_joint").rawValue,
            ARSkeleton.JointName.leftFoot.rawValue,
            ARSkeleton.JointName(rawValue: "left_foot_joint").rawValue,
            ARSkeleton.JointName.rightFoot.rawValue,
            ARSkeleton.JointName(rawValue: "right_foot_joint").rawValue,
        ]
    }

    @MainActor
    @Test func archiveStorePersistsAndReloadsCanonicalClip() throws {
        let modelConfiguration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: RecordingSessionRecord.self,
            MotionTakeRecord.self,
            configurations: modelConfiguration
        )
        let tempDirectory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let archiveStore = MotionArchiveStore(
            modelContainer: container,
            payloadFileStore: MotionPayloadFileStore(baseDirectoryURL: tempDirectory),
            playbackArtifactsFileStore: MotionPlaybackArtifactsFileStore(baseDirectoryURL: tempDirectory)
        )
        let runtimeClip = MotionClip(frames: [
            MotionFrame(
                time: 0,
                jointPositions: [
                    SIMD3<Float>(0, 1, 0),
                    SIMD3<Float>(0.2, 1.2, 0.1),
                ]
            )
        ])

        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }

        let saveResult = try archiveStore.saveTake(
            clip: runtimeClip,
            captureMode: .rearBody3D,
            recordingContext: .defaultMetronomeLoop
        )
        let storedTake = try archiveStore.loadStoredTake(
            withID: saveResult.takeID,
            fromLocalFilePath: saveResult.localFilePath
        )
        let reloadedClip = storedTake.clip

        #expect(reloadedClip.frameCount == 1)
        #expect(reloadedClip.frames[0].jointPositions.count == OdoroSkeletonDefinition.jointCount)
        #expect(FileManager.default.fileExists(atPath: saveResult.localFilePath))
        #expect(storedTake.playbackArtifacts?.stagePlayback?.stabilized.appendagePoses != nil)

        let secondSaveResult = try archiveStore.saveTake(
            clip: runtimeClip,
            captureMode: .rearBody3D,
            recordingContext: .defaultMetronomeLoop,
            existingSessionID: saveResult.sessionID
        )

        #expect(secondSaveResult.sessionID == saveResult.sessionID)
        #expect(secondSaveResult.takeID != saveResult.takeID)

        let summaries = try archiveStore.fetchTakeSummaries(inSessionID: saveResult.sessionID)
        #expect(summaries.count == 2)
        #expect(summaries.allSatisfy { !$0.isAccepted })
    }

    @MainActor
    @Test func archiveStoreAcceptsOnlyOneTakePerSession() throws {
        let modelConfiguration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: RecordingSessionRecord.self,
            MotionTakeRecord.self,
            configurations: modelConfiguration
        )
        let tempDirectory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let archiveStore = MotionArchiveStore(
            modelContainer: container,
            payloadFileStore: MotionPayloadFileStore(baseDirectoryURL: tempDirectory),
            playbackArtifactsFileStore: MotionPlaybackArtifactsFileStore(baseDirectoryURL: tempDirectory)
        )
        let runtimeClip = MotionClip(frames: [
            MotionFrame(
                time: 0,
                jointPositions: [
                    SIMD3<Float>(0, 1, 0),
                    SIMD3<Float>(0.2, 1.2, 0.1),
                ]
            )
        ])

        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }

        let firstSave = try archiveStore.saveTake(
            clip: runtimeClip,
            captureMode: .rearBody3D,
            recordingContext: .defaultMetronomeLoop
        )
        let secondSave = try archiveStore.saveTake(
            clip: runtimeClip,
            captureMode: .rearBody3D,
            recordingContext: .defaultMetronomeLoop,
            existingSessionID: firstSave.sessionID
        )

        try archiveStore.acceptTake(withID: firstSave.takeID, inSessionID: firstSave.sessionID)

        var summaries = try archiveStore.fetchTakeSummaries(inSessionID: firstSave.sessionID)
        #expect(summaries.first(where: { $0.id == firstSave.takeID })?.isAccepted == true)
        #expect(summaries.first(where: { $0.id == secondSave.takeID })?.isAccepted == false)

        try archiveStore.acceptTake(withID: secondSave.takeID, inSessionID: firstSave.sessionID)

        summaries = try archiveStore.fetchTakeSummaries(inSessionID: firstSave.sessionID)
        #expect(summaries.first(where: { $0.id == firstSave.takeID })?.isAccepted == false)
        #expect(summaries.first(where: { $0.id == secondSave.takeID })?.isAccepted == true)
    }

    @MainActor
    @Test func archiveStorePreservesImportedVideoCaptureMode() throws {
        let modelConfiguration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: RecordingSessionRecord.self,
            MotionTakeRecord.self,
            configurations: modelConfiguration
        )
        let tempDirectory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let archiveStore = MotionArchiveStore(
            modelContainer: container,
            payloadFileStore: MotionPayloadFileStore(baseDirectoryURL: tempDirectory),
            playbackArtifactsFileStore: MotionPlaybackArtifactsFileStore(baseDirectoryURL: tempDirectory)
        )
        let runtimeClip = MotionClip(frames: [
            MotionFrame(
                time: 0,
                jointPositions: [
                    SIMD3<Float>(0, 1, 0),
                    SIMD3<Float>(0.2, 1.2, 0.1),
                ]
            ),
            MotionFrame(
                time: 1.0 / 30.0,
                jointPositions: [
                    SIMD3<Float>(0.1, 1.05, 0),
                    SIMD3<Float>(0.3, 1.25, 0.12),
                ]
            )
        ])

        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }

        let saveResult = try archiveStore.saveTake(
            clip: runtimeClip,
            captureMode: .importedVideo,
            recordingContext: .defaultMetronomeLoop
        )
        let summaries = try archiveStore.fetchTakeSummaries(inSessionID: saveResult.sessionID)
        let storedTake = try archiveStore.loadStoredTake(
            withID: saveResult.takeID,
            fromLocalFilePath: saveResult.localFilePath
        )

        #expect(summaries.count == 1)
        #expect(summaries.first?.captureMode == .importedVideo)
        #expect(storedTake.playbackArtifacts == nil)
    }

    @MainActor
    @Test func studioViewModelTogglesMetronomePreviewFromMusicSelection() {
        let audioPlaybackController = TestAudioPlaybackController()
        let studio = StudioViewModel(audioPlaybackController: audioPlaybackController)
        let musicSelection = MusicSelectionViewModel(studio: studio)
        let metronome = musicSelection.availableAudioSources[0]

        studio.openMusicSelection()
        musicSelection.toggleAudioPreview(for: metronome)

        #expect(audioPlaybackController.playRequests.count == 1)
        #expect(audioPlaybackController.playRequests.first?.tempoSourceType == .metronome)
        #expect(musicSelection.isPreviewingAudioSource(metronome))

        musicSelection.toggleAudioPreview(for: metronome)

        #expect(audioPlaybackController.stopCallCount == 1)
        #expect(!musicSelection.isPreviewingAudioSource(metronome))
    }

    @MainActor
    @Test func studioViewModelStartsAndStopsMetronomeDuringRecording() {
        let audioPlaybackController = TestAudioPlaybackController()
        let studio = StudioViewModel(audioPlaybackController: audioPlaybackController)

        studio.beginRecording()

        #expect(audioPlaybackController.playRequests.count == 1)
        #expect(audioPlaybackController.playRequests.first?.bpm == MotionRecordingContext.defaultMetronomeLoop.bpm)

        studio.stopRecording()
        studio.suspendStudioForInactivity()

        #expect(audioPlaybackController.stopCallCount >= 1)
    }

    @MainActor
    @Test func studioViewModelActivatesCaptureSourceWhenPreparingPreview() {
        let source = TestMotionSource()
        let studio = StudioViewModel(
            audioPlaybackController: TestAudioPlaybackController(),
            motionSourceFactory: { _ in source }
        )

        studio.prepareCapturePreviewIfNeeded()

        #expect(source.activateCallCount == 1)
    }

    @MainActor
    @Test func motionStudioInteractorStopsRecordingAtConfiguredDuration() async {
        let source = TestMotionSource()
        var clock: TimeInterval = 0
        let interactor = MotionStudioInteractor(
            source: source,
            maximumCaptureDuration: 1,
            currentTime: { clock }
        )

        source.activate()
        interactor.beginRecording()
        source.emitFrame(at: 0, joints: 2)
        source.emitFrame(at: 0.4, joints: 2)
        await Task.yield()

        #expect(interactor.state.isRecording)

        clock = 1.05
        interactor.updateRecordingClock(now: clock)

        #expect(!interactor.state.isRecording)
        #expect(interactor.currentClip?.frameCount == 2)
        #expect(interactor.state.presentation == .stage)
    }

    @MainActor
    @Test func motionStudioInteractorAdvancesRecordingDurationWithoutFrames() {
        let source = TestMotionSource()
        var clock: TimeInterval = 10
        let interactor = MotionStudioInteractor(
            source: source,
            maximumCaptureDuration: 1,
            currentTime: { clock }
        )

        interactor.beginRecording()

        clock = 10.4
        interactor.updateRecordingClock(now: clock)

        #expect(interactor.state.isRecording)
        #expect(abs(interactor.state.recordingDuration - 0.4) < 0.001)
        #expect(interactor.state.recordedFrameCount == 0)

        clock = 11.2
        interactor.updateRecordingClock(now: clock)

        #expect(!interactor.state.isRecording)
        #expect(interactor.state.recordingDuration == 1)
        #expect(interactor.currentClip == nil)
        #expect(interactor.state.statusText == L10n.statusInsufficientMotion)
    }

    @MainActor
    @Test func motionStudioInteractorUsesCapturedClipPreparerWhenRecordingStops() async {
        let source = TestMotionSource()
        let canonicalClip = MotionClip(frames: [
            Self.canonicalFrame(time: 0),
            Self.canonicalFrame(time: 0.1, overrides: [.root: SIMD3<Float>(0.1, 1.0, 0)])
        ])
        let interactor = MotionStudioInteractor(
            source: source,
            maximumCaptureDuration: 1,
            capturedClipPreparer: TestCapturedClipPreparer(preparedClip: canonicalClip)
        )

        interactor.beginRecording()
        source.emitFrame(at: 0, joints: 2)
        source.emitFrame(at: 0.1, joints: 2)
        await Task.yield()

        interactor.stopRecording()

        #expect(interactor.currentClip?.frameCount == canonicalClip.frameCount)
        #expect(interactor.currentClip?.frames[0].jointPositions.count == OdoroSkeletonDefinition.jointCount)
        #expect(interactor.currentClip?.frames[1].jointPositions[OdoroSkeletonDefinition.index(of: .root)] == canonicalClip.frames[1].jointPositions[OdoroSkeletonDefinition.index(of: .root)])
        #expect(interactor.sourceClip?.frameCount == 2)
        #expect(interactor.sourceClip?.frames[0].jointPositions.count == 2)
    }

    private static func rotationAngle(_ rotation: simd_quatf) -> Float {
        2 * acos(min(max(abs(rotation.vector.w), -1), 1))
    }

    private static func canonicalFrame(
        time: TimeInterval,
        overrides: [OdoroJointName: SIMD3<Float>] = [:]
    ) -> MotionFrame {
        var positions = [
            OdoroJointName.root: SIMD3<Float>(0, 1.0, 0),
            .head: SIMD3<Float>(0, 1.6, 0),
            .nose: SIMD3<Float>(0, 1.68, 0.05),
            .leftShoulder: SIMD3<Float>(-0.22, 1.42, 0),
            .rightShoulder: SIMD3<Float>(0.22, 1.42, 0),
            .leftUpperArm: SIMD3<Float>(-0.34, 1.32, 0.01),
            .rightUpperArm: SIMD3<Float>(0.34, 1.32, 0.01),
            .leftElbow: SIMD3<Float>(-0.46, 1.22, 0.02),
            .rightElbow: SIMD3<Float>(0.46, 1.22, 0.02),
            .leftWrist: SIMD3<Float>(-0.66, 1.02, 0.03),
            .rightWrist: SIMD3<Float>(0.66, 1.02, 0.03),
            .leftHip: SIMD3<Float>(-0.12, 0.92, 0),
            .rightHip: SIMD3<Float>(0.12, 0.92, 0),
            .leftKnee: SIMD3<Float>(-0.12, 0.52, 0.03),
            .rightKnee: SIMD3<Float>(0.12, 0.52, 0.03),
            .leftAnkle: SIMD3<Float>(-0.12, 0.12, 0.1),
            .rightAnkle: SIMD3<Float>(0.12, 0.12, 0.1),
            .leftFoot: SIMD3<Float>(-0.12, 0.0, 0.18),
            .rightFoot: SIMD3<Float>(0.12, 0.0, 0.18),
        ]

        for (joint, position) in overrides {
            positions[joint] = position
        }

        let orderedPositions = OdoroSkeletonDefinition.jointNames.map { jointName in
            positions[jointName] ?? .zero
        }

        return MotionFrame(time: time, jointPositions: orderedPositions)
    }

    private static func arKitFrame(
        time: TimeInterval,
        overrides: [ARSkeleton.JointName: SIMD3<Float>] = [:],
        rotationOverrides: [ARSkeleton.JointName: simd_quatf] = [:]
    ) -> MotionFrame {
        let skeletonDefinition = ARSkeletonDefinition.defaultBody3D
        var positions = Array(
            repeating: SIMD3<Float>(0, -10, 0),
            count: skeletonDefinition.jointNames.count
        )
        var rotations = Array<MotionJointRotation?>(
            repeating: nil,
            count: skeletonDefinition.jointNames.count
        )

        func setJoint(_ name: ARSkeleton.JointName, position: SIMD3<Float>) {
            let index = skeletonDefinition.index(for: name)
            guard index != NSNotFound else { return }
            positions[index] = position
        }

        func setJointRotation(_ name: ARSkeleton.JointName, rotation: simd_quatf) {
            let index = skeletonDefinition.index(for: name)
            guard index != NSNotFound else { return }
            rotations[index] = MotionJointRotation(rotation)
        }

        setJoint(.root, position: SIMD3<Float>(0, 1.0, 0))
        setJoint(.head, position: SIMD3<Float>(0, 1.82, 0))
        setJoint(.leftShoulder, position: SIMD3<Float>(-0.23, 1.46, 0))
        setJoint(.rightShoulder, position: SIMD3<Float>(0.23, 1.46, 0))
        setJoint(ARSkeleton.JointName(rawValue: "left_arm_joint"), position: SIMD3<Float>(-0.38, 1.34, 0.02))
        setJoint(ARSkeleton.JointName(rawValue: "right_arm_joint"), position: SIMD3<Float>(0.38, 1.34, 0.02))
        setJoint(ARSkeleton.JointName(rawValue: "left_forearm_joint"), position: SIMD3<Float>(-0.56, 1.14, 0.03))
        setJoint(ARSkeleton.JointName(rawValue: "right_forearm_joint"), position: SIMD3<Float>(0.56, 1.14, 0.03))
        setJoint(.leftHand, position: SIMD3<Float>(-0.72, 0.94, 0.04))
        setJoint(.rightHand, position: SIMD3<Float>(0.72, 0.94, 0.04))
        setJoint(ARSkeleton.JointName(rawValue: "left_upLeg_joint"), position: SIMD3<Float>(-0.12, 0.88, 0))
        setJoint(ARSkeleton.JointName(rawValue: "right_upLeg_joint"), position: SIMD3<Float>(0.12, 0.88, 0))
        setJoint(ARSkeleton.JointName(rawValue: "left_leg_joint"), position: SIMD3<Float>(-0.12, 0.47, 0.04))
        setJoint(ARSkeleton.JointName(rawValue: "right_leg_joint"), position: SIMD3<Float>(0.12, 0.47, 0.04))
        setJoint(.leftFoot, position: SIMD3<Float>(-0.12, 0.08, 0.12))
        setJoint(ARSkeleton.JointName(rawValue: "left_foot_joint"), position: SIMD3<Float>(-0.12, 0.08, 0.12))
        setJoint(.rightFoot, position: SIMD3<Float>(0.12, 0.08, 0.12))
        setJoint(ARSkeleton.JointName(rawValue: "right_foot_joint"), position: SIMD3<Float>(0.12, 0.08, 0.12))

        for (jointName, position) in overrides {
            setJoint(jointName, position: position)
        }

        for (jointName, rotation) in rotationOverrides {
            setJointRotation(jointName, rotation: rotation)
            switch jointName.rawValue {
            case ARSkeleton.JointName.leftFoot.rawValue:
                setJointRotation(ARSkeleton.JointName(rawValue: "left_foot_joint"), rotation: rotation)
            case ARSkeleton.JointName.rightFoot.rawValue:
                setJointRotation(ARSkeleton.JointName(rawValue: "right_foot_joint"), rotation: rotation)
            default:
                break
            }
        }

        let jointRotations = rotationOverrides.isEmpty ? nil : rotations
        return MotionFrame(time: time, jointPositions: positions, jointRotations: jointRotations)
    }
}

private final class TestAudioPlaybackController: StudioAudioPlaybackControlling {
    private(set) var playRequests: [MotionRecordingContext] = []
    private(set) var stopCallCount = 0

    func playMetronome(with context: MotionRecordingContext) {
        playRequests.append(context)
    }

    func stop() {
        stopCallCount += 1
    }
}

private final class TestMotionSource: MotionSource {
    var captureMode: CaptureMode { .mock }
    let isSupported = true
    var onFrame: ((MotionFrame) -> Void)?
    var onStatusTextChange: ((String) -> Void)?
    private(set) var activateCallCount = 0

    func activate() {
        activateCallCount += 1
    }
    func deactivate() {}

    func emitFrame(at time: TimeInterval, joints: Int) {
        let positions = Array(repeating: SIMD3<Float>(0, 1, 0), count: joints)
        onFrame?(MotionFrame(time: time, jointPositions: positions))
    }
}

private struct TestCapturedClipPreparer: CapturedClipPreparing {
    let preparedClip: MotionClip

    nonisolated func prepareCapturedClip(_ clip: MotionClip) -> MotionClip {
        preparedClip
    }
}
