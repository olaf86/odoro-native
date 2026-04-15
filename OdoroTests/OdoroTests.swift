//
//  OdoroTests.swift
//  OdoroTests
//
//  Created by Yuta Ogawa on 2026/04/07.
//

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

    @Test func motionClipNormalizationMovesOriginToFootLevelAndFirstFrameCenter() {
        let clip = MotionClip(
            frames: [
                MotionFrame(
                    time: 0,
                    jointPositions: [
                        SIMD3<Float>(1, 2, 3),
                        SIMD3<Float>(3, 4, 5),
                    ]
                ),
                MotionFrame(
                    time: 0.5,
                    jointPositions: [
                        SIMD3<Float>(2, 3, 4),
                        SIMD3<Float>(4, 5, 6),
                    ]
                ),
            ]
        )

        let normalized = clip.normalizedForStage()

        #expect(normalized.frames[0].jointPositions[0] == SIMD3<Float>(-1, 0, -1))
        #expect(normalized.frames[0].jointPositions[1] == SIMD3<Float>(1, 2, 1))
        #expect(normalized.frames[1].jointPositions[0] == SIMD3<Float>(0, 1, 0))
        #expect(normalized.estimatedFrameRate == 2.0)
    }

    @Test func canonicalPoseMapperReturnsCanonicalMissingSkeletonForUnsupportedInput() {
        let frame = MotionFrame(time: 0, jointPositions: [])

        let (positions, statuses) = OdoroCanonicalPoseMapper.map(frame: frame)

        #expect(positions.count == OdoroSkeletonDefinition.jointCount)
        #expect(statuses.count == OdoroSkeletonDefinition.jointCount)
        #expect(statuses.allSatisfy { $0 == .missing })
        #expect(positions.allSatisfy { $0.simdValue == .zero })
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
    }
}
