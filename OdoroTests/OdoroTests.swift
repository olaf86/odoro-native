//
//  OdoroTests.swift
//  OdoroTests
//
//  Created by Yuta Ogawa on 2026/04/07.
//

import ARKit
import Foundation
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

    @Test func canonicalPoseMapperReturnsCanonicalMissingSkeletonForUnsupportedInput() {
        let frame = MotionFrame(time: 0, jointPositions: [])

        let mapped = OdoroCanonicalPoseMapper.map(frame: frame)

        #expect(mapped.positions.count == OdoroSkeletonDefinition.jointCount)
        #expect(mapped.statuses.count == OdoroSkeletonDefinition.jointCount)
        #expect(mapped.rotations == nil)
        #expect(mapped.statuses.allSatisfy { $0 == .missing })
        #expect(mapped.positions.allSatisfy { $0.simdValue == .zero })
    }

    @Test func motionPayloadRoundTripPreservesMappedRotations() {
        let skeletonDefinition = ARSkeletonDefinition.defaultBody3D
        var positions = Array(
            repeating: SIMD3<Float>(0, -10, 0),
            count: skeletonDefinition.jointNames.count
        )
        var rotations = Array<MotionJointRotation?>(
            repeating: nil,
            count: skeletonDefinition.jointNames.count
        )

        func setJoint(_ name: ARSkeleton.JointName, position: SIMD3<Float>, rotation: simd_quatf) {
            let index = skeletonDefinition.index(for: name)
            guard index != NSNotFound else { return }
            positions[index] = position
            rotations[index] = MotionJointRotation(rotation)
        }

        let rootRotation = simd_quatf(angle: 0.1, axis: SIMD3<Float>(0, 1, 0))
        let headRotation = simd_quatf(angle: 0.2, axis: SIMD3<Float>(1, 0, 0))
        let leftShoulderRotation = simd_quatf(angle: 0.3, axis: SIMD3<Float>(0, 0, 1))
        let rightShoulderRotation = simd_quatf(angle: -0.3, axis: SIMD3<Float>(0, 0, 1))
        let leftFootRotation = simd_quatf(angle: 0.4, axis: SIMD3<Float>(1, 1, 0))
        let rightFootRotation = simd_quatf(angle: -0.4, axis: SIMD3<Float>(1, 1, 0))

        setJoint(.root, position: SIMD3<Float>(0, 1, 0), rotation: rootRotation)
        setJoint(.head, position: SIMD3<Float>(0, 1.6, 0), rotation: headRotation)
        setJoint(.leftShoulder, position: SIMD3<Float>(-0.2, 1.4, 0), rotation: leftShoulderRotation)
        setJoint(.rightShoulder, position: SIMD3<Float>(0.2, 1.4, 0), rotation: rightShoulderRotation)
        setJoint(ARSkeleton.JointName(rawValue: "left_arm_joint"), position: SIMD3<Float>(-0.4, 1.2, 0), rotation: simd_quatf(angle: 0.15, axis: SIMD3<Float>(1, 0, 0)))
        setJoint(ARSkeleton.JointName(rawValue: "right_arm_joint"), position: SIMD3<Float>(0.4, 1.2, 0), rotation: simd_quatf(angle: -0.15, axis: SIMD3<Float>(1, 0, 0)))
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
            sourceBackend: "arkit.bodyTracking"
        )

        let reloadedFrame = payload.makeMotionClip().frames[0]

        #expect(reloadedFrame.jointRotations?.count == OdoroSkeletonDefinition.jointCount)
        #expect(reloadedFrame.jointRotations?[OdoroSkeletonDefinition.index(of: .root)] == MotionJointRotation(rootRotation))
        #expect(reloadedFrame.jointRotations?[OdoroSkeletonDefinition.index(of: .nose)] == MotionJointRotation(headRotation))
        #expect(reloadedFrame.jointRotations?[OdoroSkeletonDefinition.index(of: .leftShoulder)] == MotionJointRotation(leftShoulderRotation))
        #expect(reloadedFrame.jointRotations?[OdoroSkeletonDefinition.index(of: .rightShoulder)] == MotionJointRotation(rightShoulderRotation))
        #expect(reloadedFrame.jointRotations?[OdoroSkeletonDefinition.index(of: .leftAnkle)] == MotionJointRotation(leftFootRotation))
        #expect(reloadedFrame.jointRotations?[OdoroSkeletonDefinition.index(of: .rightFoot)] == MotionJointRotation(rightFootRotation))
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
            payloadFileStore: MotionPayloadFileStore(baseDirectoryURL: tempDirectory)
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
        let reloadedClip = try archiveStore.loadClip(fromLocalFilePath: saveResult.localFilePath)

        #expect(reloadedClip.frameCount == 1)
        #expect(reloadedClip.frames[0].jointPositions.count == OdoroSkeletonDefinition.jointCount)
        #expect(FileManager.default.fileExists(atPath: saveResult.localFilePath))

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
            payloadFileStore: MotionPayloadFileStore(baseDirectoryURL: tempDirectory)
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
            payloadFileStore: MotionPayloadFileStore(baseDirectoryURL: tempDirectory)
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

        #expect(summaries.count == 1)
        #expect(summaries.first?.captureMode == .importedVideo)
    }

    @MainActor
    @Test func studioViewModelTogglesMetronomePreviewFromMusicSelection() {
        let audioPlaybackController = TestAudioPlaybackController()
        let studio = StudioViewModel(audioPlaybackController: audioPlaybackController)
        let metronome = studio.availableAudioSources[0]

        studio.openMusicSelection()
        studio.toggleAudioPreview(for: metronome)

        #expect(audioPlaybackController.playRequests.count == 1)
        #expect(audioPlaybackController.playRequests.first?.tempoSourceType == .metronome)
        #expect(studio.isPreviewingAudioSource(metronome))

        studio.toggleAudioPreview(for: metronome)

        #expect(audioPlaybackController.stopCallCount == 1)
        #expect(!studio.isPreviewingAudioSource(metronome))
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
    @Test func motionStudioInteractorStopsRecordingAtConfiguredDuration() async {
        let source = TestMotionSource()
        let interactor = MotionStudioInteractor(source: source, maximumCaptureDuration: 1)

        source.activate()
        interactor.beginRecording()
        source.emitFrame(at: 0, joints: 2)
        source.emitFrame(at: 0.4, joints: 2)
        await Task.yield()

        #expect(interactor.state.isRecording)

        source.emitFrame(at: 1.05, joints: 2)
        await Task.yield()

        #expect(!interactor.state.isRecording)
        #expect(interactor.currentClip?.frameCount == 3)
        #expect(interactor.state.presentation == .stage)
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

    func activate() {}
    func deactivate() {}

    func emitFrame(at time: TimeInterval, joints: Int) {
        let positions = Array(repeating: SIMD3<Float>(0, 1, 0), count: joints)
        onFrame?(MotionFrame(time: time, jointPositions: positions))
    }
}
