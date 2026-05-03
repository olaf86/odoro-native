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
    @MainActor @Test func avatarCatalogMergesInstalledDownloadableAvatarWithoutDuplicates() {
        let selection = StageAvatarSelection.avatar(
            avatarID: "avatar-sample-a",
            variantID: "avatar-sample-a-usdc-v1"
        )
        let installedOption = StageAvatarOption(
            selection: selection,
            title: "Downloaded Sample A",
            subtitle: "Downloaded package installed locally.",
            systemImageName: "arrow.down.circle",
            source: .downloadable,
            installState: .installed,
            runtimeFormat: .usdc,
            runtimeAssetResourceName: nil,
            runtimeAssetURL: URL(fileURLWithPath: "/tmp/avatar-sample-a/model.usdc"),
            rigProfileID: "avatar-sample-a.v1",
            rigProfile: nil
        )

        let options = AvatarCatalog.stageOptions(installedOptions: [installedOption])
        let matchingOptions = options.filter { $0.selection == selection }

        #expect(matchingOptions.count == 1)
        #expect(matchingOptions[0].title == "Avatar Sample A")
        #expect(matchingOptions[0].installState == .installed)
        #expect(matchingOptions[0].runtimeFormat == .usdc)
        #expect(matchingOptions[0].runtimeAssetURL == installedOption.runtimeAssetURL)
    }

    @MainActor @Test func avatarAssetStoreInstallsDownloadableUSDZPackage() async throws {
        let fileManager = FileManager.default
        let tempRootURL = fileManager.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let sourceFilesURL = tempRootURL.appending(path: "remote", directoryHint: .isDirectory)
        let installRootURL = tempRootURL.appending(path: "installed", directoryHint: .isDirectory)
        defer { try? fileManager.removeItem(at: tempRootURL) }

        try fileManager.createDirectory(at: sourceFilesURL, withIntermediateDirectories: true)

        let packageManifest = AvatarPackageManifest(
            schemaVersion: 1,
            avatarID: "avatar-sample-a",
            variantID: "avatar-sample-a-usdz-v1",
            displayName: "Avatar Sample A",
            source: .downloadable,
            version: "1.0.0",
            runtimeFormat: .usdz,
            runtimeAssetFilename: "model.usdz",
            generatedRigProfileID: "avatar-sample-a.v1",
            installedAt: Date(timeIntervalSince1970: 1_776_556_800),
            sourceFilename: "Avatar Sample A.usdz",
            sourceFileByteCount: 16,
            detectedNodeNames: ["Hips"]
        )
        let rigProfile = AvatarRigProfile(
            id: "avatar-sample-a.v1",
            displayName: "Avatar Sample A Rig",
            skeletonId: OdoroSkeletonDefinition.id,
            sourceFormat: .usdz,
            runtimeFormat: .usdz,
            runtimeAssetRelativePath: "model.usdz",
            rootBoneName: "Hips",
            bindings: [],
            scaleCompensation: 1,
            floorOffset: 0,
            schemaVersion: 1
        )
        let rigDocument = AvatarRigProfileDocument(schemaVersion: 1, profile: rigProfile)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let modelURL = sourceFilesURL.appending(path: "model.usdz", directoryHint: .notDirectory)
        let packageManifestURL = sourceFilesURL.appending(path: "package_manifest.json", directoryHint: .notDirectory)
        let rigProfileURL = sourceFilesURL.appending(path: "rig_profile.json", directoryHint: .notDirectory)

        try Data("test-usdz-payload".utf8).write(to: modelURL)
        try encoder.encode(packageManifest).write(to: packageManifestURL)
        try encoder.encode(rigDocument).write(to: rigProfileURL)

        let store = AvatarAssetStore(
            fileManager: fileManager,
            baseDirectoryURL: installRootURL
        ) { remoteURL async throws in
            sourceFilesURL.appending(path: remoteURL.lastPathComponent, directoryHint: .notDirectory)
        }
        let variant = AvatarAssetVariant(
            id: "avatar-sample-a-usdz-v1",
            avatarID: "avatar-sample-a",
            version: "1.0.0",
            runtimeFormat: .usdz,
            runtimeAssetRelativePath: "avatars/avatar-sample-a/1.0.0/model.usdz",
            runtimeAssetRemoteURL: "https://example.com/model.usdz",
            runtimeAssetChecksum: nil,
            runtimeAssetSizeBytes: 16,
            packageManifestRelativePath: "avatars/avatar-sample-a/1.0.0/package_manifest.json",
            packageManifestRemoteURL: "https://example.com/package_manifest.json",
            rigProfileID: "avatar-sample-a.v1",
            rigProfileRelativePath: "avatars/avatar-sample-a/1.0.0/rig_profile.json",
            rigProfileRemoteURL: "https://example.com/rig_profile.json",
            minimumAppVersion: nil,
            minimumOSVersion: "26.4",
            installState: .notInstalled
        )

        let installedOption = try await store.installDownloadableAvatar(from: variant)
        let installedOptions = store.fetchInstalledAvatarOptions()

        #expect(installedOption.installState == .installed)
        #expect(installedOption.runtimeFormat == .usdz)
        #expect(installedOption.runtimeAssetURL?.lastPathComponent == "model.usdz")
        #expect(installedOptions.count == 1)
        #expect(installedOptions[0].selection == installedOption.selection)
        #expect(installedOptions[0].runtimeAssetURL?.lastPathComponent == "model.usdz")
    }

    @MainActor @Test func avatarAssetStoreNormalizesDownloadedUSDCMetadataWhenPublishedManifestStillSaysGLB() async throws {
        let fileManager = FileManager.default
        let tempRootURL = fileManager.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let sourceFilesURL = tempRootURL.appending(path: "remote", directoryHint: .isDirectory)
        let installRootURL = tempRootURL.appending(path: "installed", directoryHint: .isDirectory)
        defer { try? fileManager.removeItem(at: tempRootURL) }

        try fileManager.createDirectory(at: sourceFilesURL, withIntermediateDirectories: true)

        let packageManifest = AvatarPackageManifest(
            schemaVersion: 1,
            avatarID: "avatar-sample-a",
            variantID: "avatar-sample-a-glb-v1",
            displayName: "Avatar Sample A",
            source: .downloadable,
            version: "1.0.0",
            runtimeFormat: .glb,
            runtimeAssetFilename: "model.glb",
            generatedRigProfileID: "avatar-sample-a.v1",
            installedAt: Date(timeIntervalSince1970: 1_776_556_800),
            sourceFilename: "Avatar Sample A.glb",
            sourceFileByteCount: 12,
            detectedNodeNames: ["Hips"]
        )
        let rigProfile = AvatarRigProfile(
            id: "avatar-sample-a.v1",
            displayName: "Avatar Sample A Rig",
            skeletonId: OdoroSkeletonDefinition.id,
            sourceFormat: .glb,
            runtimeFormat: .glb,
            runtimeAssetRelativePath: "model.glb",
            rootBoneName: "Hips",
            bindings: [],
            scaleCompensation: 1,
            floorOffset: 0,
            schemaVersion: 1
        )
        let rigDocument = AvatarRigProfileDocument(schemaVersion: 1, profile: rigProfile)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let modelURL = sourceFilesURL.appending(path: "model.usdc", directoryHint: .notDirectory)
        let packageManifestURL = sourceFilesURL.appending(path: "package_manifest.json", directoryHint: .notDirectory)
        let rigProfileURL = sourceFilesURL.appending(path: "rig_profile.json", directoryHint: .notDirectory)

        try Data("test-usdc-payload".utf8).write(to: modelURL)
        try encoder.encode(packageManifest).write(to: packageManifestURL)
        try encoder.encode(rigDocument).write(to: rigProfileURL)

        let store = AvatarAssetStore(
            fileManager: fileManager,
            baseDirectoryURL: installRootURL
        ) { remoteURL async throws in
            sourceFilesURL.appending(path: remoteURL.lastPathComponent, directoryHint: .notDirectory)
        }
        let variant = AvatarAssetVariant(
            id: "avatar-sample-a-usdc-v1",
            avatarID: "avatar-sample-a",
            version: "1.0.0",
            runtimeFormat: .usdc,
            runtimeAssetRelativePath: "avatars/avatar-sample-a/1.0.0/model.usdc",
            runtimeAssetRemoteURL: "https://example.com/model.usdc",
            runtimeAssetChecksum: nil,
            runtimeAssetSizeBytes: 17,
            packageManifestRelativePath: "avatars/avatar-sample-a/1.0.0/package_manifest.json",
            packageManifestRemoteURL: "https://example.com/package_manifest.json",
            rigProfileID: "avatar-sample-a.v1",
            rigProfileRelativePath: "avatars/avatar-sample-a/1.0.0/rig_profile.json",
            rigProfileRemoteURL: "https://example.com/rig_profile.json",
            minimumAppVersion: nil,
            minimumOSVersion: "26.4",
            installState: .notInstalled
        )

        let installedOption = try await store.installDownloadableAvatar(from: variant)
        let installedOptions = store.fetchInstalledAvatarOptions()

        #expect(installedOption.installState == .installed)
        #expect(installedOption.runtimeFormat == .usdc)
        #expect(installedOption.runtimeAssetURL?.lastPathComponent == "model.usdc")
        #expect(installedOptions.count == 1)
        #expect(installedOptions[0].selection == installedOption.selection)
        #expect(installedOptions[0].runtimeFormat == .usdc)
        #expect(installedOptions[0].runtimeAssetURL?.lastPathComponent == "model.usdc")
    }

    @MainActor @Test func avatarAssetStoreRequiresRemoteRuntimeAssetLocationForDownloadableAvatarInstall() async throws {
        let fileManager = FileManager.default
        let tempRootURL = fileManager.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let installRootURL = tempRootURL.appending(path: "installed", directoryHint: .isDirectory)
        defer { try? fileManager.removeItem(at: tempRootURL) }

        try fileManager.createDirectory(at: tempRootURL, withIntermediateDirectories: true)
        let store = AvatarAssetStore(
            fileManager: fileManager,
            baseDirectoryURL: installRootURL
        )
        let variant = AvatarAssetVariant(
            id: "avatar-sample-a-usdc-v1",
            avatarID: "avatar-sample-a",
            version: "1.0.0",
            runtimeFormat: .usdc,
            runtimeAssetRelativePath: "",
            runtimeAssetRemoteURL: nil,
            runtimeAssetChecksum: nil,
            runtimeAssetSizeBytes: 16,
            packageManifestRelativePath: "avatars/avatar-sample-a/1.0.0/package_manifest.json",
            packageManifestRemoteURL: nil,
            rigProfileID: "avatar-sample-a.v1",
            rigProfileRelativePath: "avatars/avatar-sample-a/1.0.0/rig_profile.json",
            rigProfileRemoteURL: nil,
            minimumAppVersion: nil,
            minimumOSVersion: "26.4",
            installState: .notInstalled
        )

        do {
            _ = try await store.installDownloadableAvatar(from: variant)
            Issue.record("Expected installDownloadableAvatar to fail when the runtime asset location is missing.")
        } catch let error as AvatarAssetStore.StoreError {
            #expect(error == .missingRemoteAssetURL("runtime asset"))
            #expect(store.fetchInstalledAvatarOptions().isEmpty)
        }
    }

    @MainActor @Test func avatarAssetStoreBuildsRemoteURLsFromRelativePathsWhenBaseURLIsConfigured() async throws {
        let fileManager = FileManager.default
        let tempRootURL = fileManager.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let sourceFilesURL = tempRootURL.appending(path: "remote", directoryHint: .isDirectory)
        let installRootURL = tempRootURL.appending(path: "installed", directoryHint: .isDirectory)
        defer { try? fileManager.removeItem(at: tempRootURL) }

        try fileManager.createDirectory(at: sourceFilesURL, withIntermediateDirectories: true)

        let packageManifest = AvatarPackageManifest(
            schemaVersion: 1,
            avatarID: "avatar-sample-a",
            variantID: "avatar-sample-a-usdc-v1",
            displayName: "Avatar Sample A",
            source: .downloadable,
            version: "1.0.0",
            runtimeFormat: .usdc,
            runtimeAssetFilename: "model.usdc",
            generatedRigProfileID: "avatar-sample-a.v1",
            installedAt: Date(timeIntervalSince1970: 1_776_556_800),
            sourceFilename: "Avatar Sample A.usdc",
            sourceFileByteCount: 16,
            detectedNodeNames: ["Hips"]
        )
        let rigProfile = AvatarRigProfile(
            id: "avatar-sample-a.v1",
            displayName: "Avatar Sample A Rig",
            skeletonId: OdoroSkeletonDefinition.id,
            sourceFormat: .usdc,
            runtimeFormat: .usdc,
            runtimeAssetRelativePath: "model.usdc",
            rootBoneName: "Hips",
            bindings: [],
            scaleCompensation: 1,
            floorOffset: 0,
            schemaVersion: 1
        )
        let rigDocument = AvatarRigProfileDocument(schemaVersion: 1, profile: rigProfile)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let modelURL = sourceFilesURL.appending(path: "model.usdc", directoryHint: .notDirectory)
        let packageManifestURL = sourceFilesURL.appending(path: "package_manifest.json", directoryHint: .notDirectory)
        let rigProfileURL = sourceFilesURL.appending(path: "rig_profile.json", directoryHint: .notDirectory)

        try Data("test-usdc-payload".utf8).write(to: modelURL)
        try encoder.encode(packageManifest).write(to: packageManifestURL)
        try encoder.encode(rigDocument).write(to: rigProfileURL)

        let store = AvatarAssetStore(
            fileManager: fileManager,
            baseDirectoryURL: installRootURL,
            remoteBaseURL: URL(string: "https://example.com/assets")
        ) { remoteURL async throws in
            sourceFilesURL.appending(path: remoteURL.lastPathComponent, directoryHint: .notDirectory)
        }
        let variant = AvatarAssetVariant(
            id: "avatar-sample-a-usdc-v1",
            avatarID: "avatar-sample-a",
            version: "1.0.0",
            runtimeFormat: .usdc,
            runtimeAssetRelativePath: "avatars/avatar-sample-a/1.0.0/model.usdc",
            runtimeAssetRemoteURL: nil,
            runtimeAssetChecksum: nil,
            runtimeAssetSizeBytes: 17,
            packageManifestRelativePath: "avatars/avatar-sample-a/1.0.0/package_manifest.json",
            packageManifestRemoteURL: nil,
            rigProfileID: "avatar-sample-a.v1",
            rigProfileRelativePath: "avatars/avatar-sample-a/1.0.0/rig_profile.json",
            rigProfileRemoteURL: nil,
            minimumAppVersion: nil,
            minimumOSVersion: "26.4",
            installState: .notInstalled
        )

        let installedOption = try await store.installDownloadableAvatar(from: variant)

        #expect(installedOption.installState == .installed)
        #expect(installedOption.runtimeFormat == .usdc)
        #expect(installedOption.runtimeAssetURL?.lastPathComponent == "model.usdc")
    }

    @Test func appConfigurationTreatsMissingAvatarStorageBaseURLAsUnset() {
        #expect(
            AppConfiguration.resolvedAvatarStorageBaseURL(from: nil) == nil
        )
        #expect(
            AppConfiguration.resolvedAvatarStorageBaseURL(from: "   ") == nil
        )
        #expect(
            AppConfiguration.resolvedAvatarStorageBaseURL(from: "https:") == nil
        )
        #expect(
            AppConfiguration.resolvedAvatarStorageBaseURL(
                from: "https://storage.googleapis.com/odoro-assets"
            )?.absoluteString == "https://storage.googleapis.com/odoro-assets"
        )
    }

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

    @Test func motionClipNormalizationUsesCanonicalRootAsOrigin() {
        let root = SIMD3<Float>(0.32, 1.0, 0.14)
        let clip = MotionClip(frames: [
            Self.canonicalFrame(
                time: 0,
                overrides: [.root: root]
            )
        ])

        let normalized = clip.normalizedForStage()
        let normalizedRoot = normalized.frames[0].jointPositions[OdoroSkeletonDefinition.index(of: .root)]

        #expect(abs(normalizedRoot.x) < 0.0001)
        #expect(abs(normalizedRoot.z) < 0.0001)
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

    @Test func motionClipStageStabilizerRigSafeProfileSkipsCanonicalBoneConstraints() {
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
        let clip = MotionClip(frames: [baselineFrame, spikedFrame, recoveredFrame])

        let displaySafe = stabilizer.stabilize(clip, profile: .displaySafe)
        let rigSafe = stabilizer.stabilize(clip, profile: .rigSafe)

        let leftAnkleIndex = OdoroSkeletonDefinition.index(of: .leftAnkle)
        let leftFootIndex = OdoroSkeletonDefinition.index(of: .leftFoot)
        let referenceLength = simd_distance(
            baselineFrame.jointPositions[leftAnkleIndex],
            baselineFrame.jointPositions[leftFootIndex]
        )
        let displaySafeSpikeLength = simd_distance(
            displaySafe[1].jointPositions[leftAnkleIndex],
            displaySafe[1].jointPositions[leftFootIndex]
        )
        let rigSafeSpikeLength = simd_distance(
            rigSafe[1].jointPositions[leftAnkleIndex],
            rigSafe[1].jointPositions[leftFootIndex]
        )

        #expect(abs(displaySafeSpikeLength - referenceLength) < abs(rigSafeSpikeLength - referenceLength))
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

    @Test func motionClipStageStabilizerTracksCanonicalRootWhenUpperBodyShifts() {
        let stabilizer = MotionClipStageStabilizer()
        let baseFrame = Self.canonicalFrame(time: 0)
        let upperBodyJoints: [OdoroJointName] = [
            .head,
            .nose,
            .leftShoulder,
            .rightShoulder,
            .leftUpperArm,
            .rightUpperArm,
            .leftElbow,
            .rightElbow,
            .leftWrist,
            .rightWrist,
        ]
        let upperBodyShift = SIMD3<Float>(0.9, 0, 0)

        func shiftedUpperBody(overrides: [OdoroJointName: SIMD3<Float>] = [:]) -> [OdoroJointName: SIMD3<Float>] {
            var resolved = overrides
            for joint in upperBodyJoints {
                let basePosition = baseFrame.jointPositions[OdoroSkeletonDefinition.index(of: joint)]
                resolved[joint] = (resolved[joint] ?? basePosition) + upperBodyShift
            }
            return resolved
        }

        let clip = MotionClip(frames: [
            baseFrame,
            Self.canonicalFrame(
                time: 1.0 / 30.0,
                overrides: shiftedUpperBody(overrides: [.root: SIMD3<Float>(0.03, 1.0, 0)])
            ),
            Self.canonicalFrame(
                time: 2.0 / 30.0,
                overrides: [.root: SIMD3<Float>(0.06, 1.0, 0)]
            ),
        ])

        let stabilized = stabilizer.stabilize(clip)
        let rootIndex = OdoroSkeletonDefinition.index(of: .root)
        let stabilizedRootX = stabilized[1].jointPositions[rootIndex].x

        #expect(abs(stabilizedRootX - 0.03) < 0.08)
        #expect(abs(stabilizedRootX - clip.frames[1].jointPositions[rootIndex].x) < 0.08)
    }

    @Test func motionClipStageStabilizerStronglyDampensCanonicalRootMistracks() {
        let stabilizer = MotionClipStageStabilizer()

        func translatedFrame(time: TimeInterval, xOffset: Float) -> MotionFrame {
            let baseFrame = Self.canonicalFrame(time: time)
            let translatedPositions = baseFrame.jointPositions.map { position in
                SIMD3<Float>(position.x + xOffset, position.y, position.z)
            }
            return MotionFrame(
                time: time,
                jointPositions: translatedPositions,
                jointRotations: baseFrame.jointRotations
            )
        }

        let clip = MotionClip(frames: [
            translatedFrame(time: 0, xOffset: 0),
            translatedFrame(time: 1.0 / 30.0, xOffset: 1.8),
            translatedFrame(time: 2.0 / 30.0, xOffset: 0.06),
        ])

        let stabilized = stabilizer.stabilize(clip)
        let rootIndex = OdoroSkeletonDefinition.index(of: .root)
        let mistrackedRootX = stabilized[1].jointPositions[rootIndex].x
        let recoveredRootX = stabilized[2].jointPositions[rootIndex].x

        #expect(mistrackedRootX < 0.2)
        #expect(abs(recoveredRootX - 0.06) < 0.08)
    }

    @Test func motionClipStageStabilizerDoesNotKeepGlidingAfterCanonicalRootRecovery() {
        let stabilizer = MotionClipStageStabilizer()

        func translatedFrame(time: TimeInterval, xOffset: Float) -> MotionFrame {
            let baseFrame = Self.canonicalFrame(time: time)
            let translatedPositions = baseFrame.jointPositions.map { position in
                SIMD3<Float>(position.x + xOffset, position.y, position.z)
            }
            return MotionFrame(
                time: time,
                jointPositions: translatedPositions,
                jointRotations: baseFrame.jointRotations
            )
        }

        let frames = [
            translatedFrame(time: 0, xOffset: 0),
            translatedFrame(time: 1.0 / 30.0, xOffset: 1.8),
            translatedFrame(time: 2.0 / 30.0, xOffset: 0.06),
            translatedFrame(time: 3.0 / 30.0, xOffset: 0.06),
            translatedFrame(time: 4.0 / 30.0, xOffset: 0.06),
            translatedFrame(time: 5.0 / 30.0, xOffset: 0.06),
            translatedFrame(time: 6.0 / 30.0, xOffset: 0.06),
        ]

        let stabilized = stabilizer.stabilize(MotionClip(frames: frames))
        let rootIndex = OdoroSkeletonDefinition.index(of: .root)
        let recoveredXs = stabilized.dropFirst(2).map { $0.jointPositions[rootIndex].x }

        #expect(recoveredXs.allSatisfy { abs($0 - 0.06) < 0.12 })
        #expect(abs(recoveredXs.last ?? 0 - 0.06) < 0.08)
    }

    @Test func motionClipStageStabilizerDoesNotKeepLiftingAfterCanonicalRootHeightSpike() {
        let stabilizer = MotionClipStageStabilizer()

        func frame(time: TimeInterval, rootY: Float) -> MotionFrame {
            Self.canonicalFrame(
                time: time,
                overrides: [.root: SIMD3<Float>(0, rootY, 0)]
            )
        }

        let stabilized = stabilizer.stabilize(
            MotionClip(frames: [
                frame(time: 0, rootY: 1.0),
                frame(time: 1.0 / 30.0, rootY: 1.9),
                frame(time: 2.0 / 30.0, rootY: 1.0),
                frame(time: 3.0 / 30.0, rootY: 1.0),
                frame(time: 4.0 / 30.0, rootY: 1.0),
                frame(time: 5.0 / 30.0, rootY: 1.0),
            ])
        )

        let rootIndex = OdoroSkeletonDefinition.index(of: .root)
        let recoveredYs = stabilized.dropFirst(2).map { $0.jointPositions[rootIndex].y }
        #expect(recoveredYs.allSatisfy { $0 < 1.2 })
        #expect(abs((recoveredYs.last ?? 0) - 1.0) < 0.08)
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

    @Test func rearBodyInferenceKeepsFootForwardAlignedWithBodyWhenFootRotationIsSideways() throws {
        let baseFrame = Self.canonicalFrame(time: 0)
        let leftFootIndex = OdoroSkeletonDefinition.index(of: .leftFoot)
        let rightFootIndex = OdoroSkeletonDefinition.index(of: .rightFoot)
        var rotations = Array<MotionJointRotation?>(
            repeating: nil,
            count: OdoroSkeletonDefinition.jointCount
        )
        let sidewaysRotation = MotionJointRotation(
            simd_quatf(angle: -.pi / 2, axis: SIMD3<Float>(0, 1, 0))
        )
        rotations[leftFootIndex] = sidewaysRotation
        rotations[rightFootIndex] = sidewaysRotation

        let clip = MotionClip(frames: [
            MotionFrame(
                time: 0,
                jointPositions: baseFrame.jointPositions,
                jointRotations: rotations
            )
        ])

        let inference = RearBody3DAppendagePoseEstimator().estimatePoses(for: clip)
        let leftFoot = try #require(inference.frames.first?.feet.left)
        let rightFoot = try #require(inference.frames.first?.feet.right)

        #expect(leftFoot.forward.z > 0.75)
        #expect(rightFoot.forward.z > 0.75)
        #expect(abs(leftFoot.forward.x) < 0.35)
        #expect(abs(rightFoot.forward.x) < 0.35)
    }

    @Test func rearBodyInferenceSmoothsFootForwardAcrossFrames() throws {
        let leftFootIndex = OdoroSkeletonDefinition.index(of: .leftFoot)
        var sidewaysRotations = Array<MotionJointRotation?>(
            repeating: nil,
            count: OdoroSkeletonDefinition.jointCount
        )
        sidewaysRotations[leftFootIndex] = MotionJointRotation(
            simd_quatf(angle: -.pi / 2, axis: SIMD3<Float>(0, 1, 0))
        )

        let clip = MotionClip(frames: [
            Self.canonicalFrame(time: 0),
            MotionFrame(
                time: 1.0 / 30.0,
                jointPositions: Self.canonicalFrame(time: 1.0 / 30.0).jointPositions,
                jointRotations: sidewaysRotations
            ),
        ])

        let inference = RearBody3DAppendagePoseEstimator().estimatePoses(for: clip)
        let leftFoot = try #require(inference.frames[1].feet.left)

        #expect(leftFoot.forward.z > 0.8)
        #expect(abs(leftFoot.forward.x) < 0.3)
    }

    @Test func rearBodyInferenceDoesNotLetPreviousFootForwardFlipBehindBody() throws {
        let leftFootIndex = OdoroSkeletonDefinition.index(of: .leftFoot)
        var backwardRotations = Array<MotionJointRotation?>(
            repeating: nil,
            count: OdoroSkeletonDefinition.jointCount
        )
        backwardRotations[leftFootIndex] = MotionJointRotation(
            simd_quatf(angle: .pi, axis: SIMD3<Float>(0, 1, 0))
        )

        let clip = MotionClip(frames: [
            MotionFrame(
                time: 0,
                jointPositions: Self.canonicalFrame(time: 0).jointPositions,
                jointRotations: backwardRotations
            ),
            Self.canonicalFrame(time: 1.0 / 30.0),
        ])

        let inference = RearBody3DAppendagePoseEstimator().estimatePoses(for: clip)
        let leftFoot = try #require(inference.frames[1].feet.left)

        #expect(leftFoot.forward.z > 0.7)
        #expect(simd_dot(leftFoot.forward, SIMD3<Float>(0, 0, 1)) > 0.7)
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

    @Test func stagePreparedPlaybackBuilderCachesRearBodyInferenceOnPreparedVariants() throws {
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
        #expect(prepared.raw.purpose == .display)
        #expect(prepared.raw.processingStage == .raw)
        #expect(prepared.raw.skeletonDefinition == .source)
        #expect(prepared.raw.integrity == .rigSafe)
        let rigVariant = try #require(prepared.variant(purpose: .avatarRig, processingStage: .stabilized))
        #expect(rigVariant.skeletonDefinition == .source)
        #expect(rigVariant.integrity == .rigSafe)
        #expect(rigVariant.stabilizationProfile == .rigSafe)
        #expect(prepared.canonical.clip != nil)
        #expect(prepared.canonical.purpose == .display)
        #expect(prepared.canonical.processingStage == .canonical)
        #expect(prepared.canonical.skeletonDefinition == .odoroCanonical)
        #expect(prepared.canonical.integrity == .displaySafe)
        #expect(prepared.canonical.appendagePoses?.frames.count == prepared.canonical.clip?.frames.count)
        #expect(prepared.stabilized.purpose == .display)
        #expect(prepared.stabilized.processingStage == .stabilized)
        #expect(prepared.stabilized.skeletonDefinition == .odoroCanonical)
        #expect(prepared.stabilized.integrity == .displaySafe)
        #expect(prepared.stabilized.stabilizationProfile == .displaySafe)
        #expect(prepared.stabilized.appendagePoses?.frames.count == prepared.stabilized.clip?.frames.count)
        #expect(prepared.canonical.cameraPreset != nil)
        #expect(prepared.stabilized.cameraPreset != nil)
        #expect(prepared.avatarRigVariant?.purpose == .avatarRig)
        #expect(prepared.avatarRigVariant?.processingStage == .stabilized)
        #expect(prepared.avatarRigVariant?.integrity == .rigSafe)
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

    @Test func stagePreparedPlaybackBuilderUsesStoredHintsWhenSourceClipIsUnavailable() throws {
        let playbackClip = MotionClip(frames: [
            Self.canonicalFrame(time: 0),
            Self.canonicalFrame(time: 1.0 / 30.0),
        ])
        let storedHints = try #require(
            MotionPlaybackHintsBuilder().build(
                playbackClip: playbackClip,
                captureMode: .rearBody3D
            )
        )

        let prepared = StagePreparedPlaybackBuilder().prepare(
            sourceClip: nil,
            playbackClip: playbackClip,
            captureMode: .rearBody3D,
            hints: storedHints
        )

        #expect(prepared.canonical.appendagePoses == storedHints.stage?.canonical.appendagePoses)
        #expect(prepared.stabilized.appendagePoses == storedHints.stage?.stabilized.appendagePoses)
        #expect(prepared.canonical.cameraPreset == storedHints.stage?.canonical.cameraPreset)
        #expect(prepared.stabilized.cameraPreset == storedHints.stage?.stabilized.cameraPreset)
        #expect(prepared.raw.integrity == .displaySafe)
        #expect(prepared.raw.skeletonDefinition == .odoroCanonical)
        #expect(prepared.variant(purpose: .avatarRig, processingStage: .stabilized) == nil)
        #expect(prepared.avatarRigVariant == nil)
    }

    @Test func stagePlaybackCameraEstimatorPlacesCameraInFrontOfRepresentativeBodyFacing() throws {
        let estimator = StagePlaybackCameraEstimator()
        let clip = MotionClip(frames: [
            Self.canonicalFrame(
                time: 0,
                overrides: [
                    .root: SIMD3<Float>(0.4, 1.0, 0.1),
                    .head: SIMD3<Float>(0.4, 1.6, 0.1),
                    .nose: SIMD3<Float>(0.4, 1.68, 0.16),
                    .leftShoulder: SIMD3<Float>(0.18, 1.42, 0.1),
                    .rightShoulder: SIMD3<Float>(0.62, 1.42, 0.1),
                    .leftHip: SIMD3<Float>(0.28, 0.92, 0.1),
                    .rightHip: SIMD3<Float>(0.52, 0.92, 0.1),
                ]
            ),
            Self.canonicalFrame(
                time: 1.0 / 30.0,
                overrides: [
                    .root: SIMD3<Float>(0.6, 1.0, 0.12),
                    .head: SIMD3<Float>(0.6, 1.6, 0.12),
                    .nose: SIMD3<Float>(0.6, 1.68, 0.18),
                    .leftShoulder: SIMD3<Float>(0.38, 1.42, 0.12),
                    .rightShoulder: SIMD3<Float>(0.82, 1.42, 0.12),
                    .leftHip: SIMD3<Float>(0.48, 0.92, 0.12),
                    .rightHip: SIMD3<Float>(0.72, 0.92, 0.12),
                ]
            ),
        ])

        let preset = try #require(estimator.estimate(for: clip))

        #expect(abs(preset.lookAtSIMD.x - 0.5) < 0.12)
        #expect(preset.positionSIMD.z > preset.lookAtSIMD.z + 3.0)
        #expect(abs(preset.positionSIMD.x - preset.lookAtSIMD.x) < 0.2)
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
            sourceNeutralLocalRotation: nil,
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
            sourceNeutralLocalRotation: nil,
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

    @Test func stageRendererRigContinuityCorrectionDampensLargeRotationJumps() {
        let previous = Transform(
            scale: .one,
            rotation: simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0)),
            translation: SIMD3<Float>(0, 0.2, 0)
        )
        let target = Transform(
            scale: .one,
            rotation: simd_quatf(angle: .pi, axis: SIMD3<Float>(0, 1, 0)),
            translation: SIMD3<Float>(0.4, 0.6, -0.2)
        )

        let stabilized = StagePlaybackRenderer.stabilizedRigLocalTransform(
            previous: previous,
            target: target
        )

        #expect(Self.rotationAngle(stabilized.rotation) < Self.rotationAngle(target.rotation))
        #expect(Self.rotationAngle(stabilized.rotation) > 0)
        #expect(stabilized.translation == target.translation)
    }

    @Test func stageRendererRigContinuityTranslationSmoothingDampensRootPositionSpikes() {
        let previous = Transform(
            scale: .one,
            rotation: simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0)),
            translation: SIMD3<Float>(0, 0, 0)
        )
        let spikeTarget = Transform(
            scale: .one,
            rotation: simd_quatf(angle: 0.05, axis: SIMD3<Float>(0, 1, 0)),
            translation: SIMD3<Float>(0.4, 0.6, 0)
        )

        let withoutSmoothing = StagePlaybackRenderer.stabilizedRigLocalTransform(
            previous: previous,
            target: spikeTarget,
            smoothsTranslation: false
        )
        let withSmoothing = StagePlaybackRenderer.stabilizedRigLocalTransform(
            previous: previous,
            target: spikeTarget,
            smoothsTranslation: true
        )

        #expect(withoutSmoothing.translation == spikeTarget.translation)
        #expect(simd_length(withSmoothing.translation) < simd_length(spikeTarget.translation))
        #expect(simd_length(withSmoothing.translation) > 0)
    }

    @Test func stageRendererRigContinuityHeadRotationAlphaProducesLessMotionThanDefault() {
        let previous = Transform(
            scale: .one,
            rotation: simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0)),
            translation: .zero
        )
        let target = Transform(
            scale: .one,
            rotation: simd_quatf(angle: 0.25, axis: SIMD3<Float>(0, 1, 0)),
            translation: .zero
        )

        let defaultStabilized = StagePlaybackRenderer.stabilizedRigLocalTransform(
            previous: previous,
            target: target
        )
        let headStabilized = StagePlaybackRenderer.stabilizedRigLocalTransform(
            previous: previous,
            target: target,
            maximumRotationAlpha: 0.62
        )

        #expect(Self.rotationAngle(headStabilized.rotation) < Self.rotationAngle(defaultStabilized.rotation))
        #expect(Self.rotationAngle(headStabilized.rotation) > 0)
    }

    @Test func stageRendererRigContinuityTranslationSmoothingPassesThroughSmallDeltas() {
        let previous = Transform(
            scale: .one,
            rotation: simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0)),
            translation: SIMD3<Float>(0.1, 0, 0)
        )
        let smallTarget = Transform(
            scale: .one,
            rotation: simd_quatf(angle: 0.02, axis: SIMD3<Float>(0, 1, 0)),
            translation: SIMD3<Float>(0.115, 0, 0)
        )

        let smoothed = StagePlaybackRenderer.stabilizedRigLocalTransform(
            previous: previous,
            target: smallTarget,
            smoothsTranslation: true
        )

        // Small movement (1.5cm) should follow at high alpha — well above 70% of target distance
        let targetDist = simd_length(smallTarget.translation - previous.translation)
        let smoothedDist = simd_length(smoothed.translation - previous.translation)
        #expect(smoothedDist / targetDist > 0.7)
    }

    @Test func stageRendererRigContinuityCorrectionPassesThroughFirstTargetPose() {
        let target = Transform(
            scale: SIMD3<Float>(1.2, 0.9, 1.1),
            rotation: simd_quatf(angle: .pi / 3, axis: SIMD3<Float>(1, 0, 0)),
            translation: SIMD3<Float>(0.1, 0.3, -0.1)
        )

        let stabilized = StagePlaybackRenderer.stabilizedRigLocalTransform(
            previous: nil,
            target: target
        )

        #expect(stabilized == target)
    }

    @Test func stageRendererBindPoseNeutralRotationKeepsBindPoseAtSourceRest() {
        let baseRotation = simd_quatf(angle: .pi / 2, axis: SIMD3<Float>(1, 0, 0))
        let sourceNeutralLocalRotation = simd_quatf(angle: .pi / 3, axis: SIMD3<Float>(0, 1, 0))
        let localTransform = StagePlaybackRenderer.makeRigLocalTransform(
            preserving: Transform(scale: .one, rotation: baseRotation, translation: SIMD3<Float>(0.1, 0.2, 0.3)),
            worldRotation: sourceNeutralLocalRotation,
            worldPosition: .zero,
            parentWorldRotation: nil,
            parentWorldPosition: nil,
            floorOffset: 0,
            translationMode: .bindPose,
            preservesBindPoseRotation: false,
            sourceNeutralLocalRotation: sourceNeutralLocalRotation,
            rotationWeight: 1
        )

        #expect(Self.rotationAngle(baseRotation.inverse * localTransform.rotation) < 0.0001)
        #expect(localTransform.translation == SIMD3<Float>(0.1, 0.2, 0.3))
    }

    @Test func stageRendererBindPoseNeutralRotationAppliesOnlyMotionDeltaOnTopOfBindPose() {
        let parentWorldRotation = simd_quatf(angle: .pi / 4, axis: SIMD3<Float>(0, 1, 0))
        let baseRotation = simd_quatf(angle: .pi / 2, axis: SIMD3<Float>(1, 0, 0))
        let sourceNeutralLocalRotation = simd_quatf(angle: .pi / 6, axis: SIMD3<Float>(0, 0, 1))
        let motionDelta = simd_quatf(angle: .pi / 5, axis: SIMD3<Float>(1, 0, 0))
        let localTransform = StagePlaybackRenderer.makeRigLocalTransform(
            preserving: Transform(scale: .one, rotation: baseRotation, translation: .zero),
            worldRotation: parentWorldRotation * sourceNeutralLocalRotation * motionDelta,
            worldPosition: .zero,
            parentWorldRotation: parentWorldRotation,
            parentWorldPosition: .zero,
            floorOffset: 0,
            translationMode: .bindPose,
            preservesBindPoseRotation: false,
            sourceNeutralLocalRotation: sourceNeutralLocalRotation,
            rotationWeight: 1
        )

        let expectedRotation = baseRotation * motionDelta
        #expect(Self.rotationAngle(expectedRotation.inverse * localTransform.rotation) < 0.002)
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
                    boneName: "left_shoulder",
                    sourceJoint: .init(canonicalJoint: .leftShoulder),
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
            sourceClipFileStore: MotionSourceClipFileStore(baseDirectoryURL: tempDirectory),
            hintsFileStore: MotionPlaybackHintsFileStore(baseDirectoryURL: tempDirectory)
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
            sourceClip: runtimeClip,
            captureMode: .rearBody3D,
            recordingContext: .defaultMetronomeLoop
        )
        let storedTake = try archiveStore.loadStoredTake(withID: saveResult.takeID)
        let reloadedClip = storedTake.clip

        #expect(reloadedClip.frameCount == 1)
        #expect(reloadedClip.frames[0].jointPositions.count == OdoroSkeletonDefinition.jointCount)
        #expect(FileManager.default.fileExists(atPath: saveResult.localFilePath))
        #expect(storedTake.hints?.stage?.stabilized.appendagePoses != nil)

        let secondSaveResult = try archiveStore.saveTake(
            sourceClip: runtimeClip,
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
    @Test func archiveStorePersistsAndReloadsUnprocessedSourceClip() throws {
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
            sourceClipFileStore: MotionSourceClipFileStore(baseDirectoryURL: tempDirectory),
            hintsFileStore: MotionPlaybackHintsFileStore(baseDirectoryURL: tempDirectory)
        )
        let sourceClip = MotionClip(frames: [
            MotionFrame(
                time: 0,
                jointPositions: [
                    SIMD3<Float>(0, 1.0, 0),
                    SIMD3<Float>(0.2, 1.3, 0.1),
                    SIMD3<Float>(-0.1, 0.7, -0.05),
                ],
                jointRotations: [
                    MotionJointRotation(simd_quatf(angle: 0.1, axis: SIMD3<Float>(0, 1, 0))),
                    MotionJointRotation(simd_quatf(angle: -0.2, axis: SIMD3<Float>(1, 0, 0))),
                    nil,
                ]
            )
        ])
        let expectedPlaybackClip = MotionPlaybackClipPreparer(captureMode: .rearBody3D)
            .prepareCapturedClip(sourceClip)

        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }

        let saveResult = try archiveStore.saveTake(
            sourceClip: sourceClip,
            captureMode: .rearBody3D,
            recordingContext: .defaultMetronomeLoop
        )
        let sourceClipFileStore = MotionSourceClipFileStore(baseDirectoryURL: tempDirectory)
        let sourceClipData = try Data(contentsOf: sourceClipFileStore.sourceClipURL(for: saveResult.takeID))
        let storedTake = try archiveStore.loadStoredTake(withID: saveResult.takeID)

        #expect(sourceClipData.starts(with: Data("OSRC".utf8)))
        let reloadedSourceClip = storedTake.sourceClip
        #expect(reloadedSourceClip.frameCount == 1)
        #expect(reloadedSourceClip.frames[0].jointPositions.count == 3)
        #expect(reloadedSourceClip.frames[0].jointPositions[1] == sourceClip.frames[0].jointPositions[1])
        #expect(reloadedSourceClip.frames[0].jointRotations?[0] == sourceClip.frames[0].jointRotations?[0])
        #expect(storedTake.clip.frameCount == expectedPlaybackClip.frameCount)
        #expect(storedTake.clip.frames[0].jointPositions == expectedPlaybackClip.frames[0].jointPositions)
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
            sourceClipFileStore: MotionSourceClipFileStore(baseDirectoryURL: tempDirectory),
            hintsFileStore: MotionPlaybackHintsFileStore(baseDirectoryURL: tempDirectory)
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
            sourceClip: runtimeClip,
            captureMode: .rearBody3D,
            recordingContext: .defaultMetronomeLoop
        )
        let secondSave = try archiveStore.saveTake(
            sourceClip: runtimeClip,
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
            sourceClipFileStore: MotionSourceClipFileStore(baseDirectoryURL: tempDirectory),
            hintsFileStore: MotionPlaybackHintsFileStore(baseDirectoryURL: tempDirectory)
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
            sourceClip: runtimeClip,
            captureMode: .importedVideo,
            recordingContext: .defaultMetronomeLoop
        )
        let summaries = try archiveStore.fetchTakeSummaries(inSessionID: saveResult.sessionID)
        let storedTake = try archiveStore.loadStoredTake(withID: saveResult.takeID)

        #expect(summaries.count == 1)
        #expect(summaries.first?.captureMode == .importedVideo)
        #expect(storedTake.hints?.stage?.stabilized.cameraPreset != nil)
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
    @Test func studioViewModelPersistsRecordedClipWhenEnteringStage() async throws {
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
            sourceClipFileStore: MotionSourceClipFileStore(baseDirectoryURL: tempDirectory),
            hintsFileStore: MotionPlaybackHintsFileStore(baseDirectoryURL: tempDirectory)
        )
        let source = TestMotionSource()
        let studio = StudioViewModel(
            archiveStore: archiveStore,
            audioPlaybackController: TestAudioPlaybackController(),
            motionSourceFactory: { _ in source }
        )

        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }

        studio.beginRecording()
        source.emitFrame(at: 0, joints: 2)
        source.emitFrame(at: 0.1, joints: 2)
        await Task.yield()

        studio.stopRecording()
        for _ in 0..<20 where studio.libraryClips.isEmpty || studio.currentSessionTakes.isEmpty {
            await Task.yield()
        }

        #expect(studio.screen == .stage)
        #expect(studio.currentSessionTakes.count == 1)
        #expect(studio.libraryClips.count == 1)
        #expect(studio.currentTakeID == studio.currentSessionTakes.first?.id)
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

        source.activate(for: .recording)
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
    private(set) var lastActivity: MotionSourceActivity?

    func activate(for activity: MotionSourceActivity) {
        activateCallCount += 1
        lastActivity = activity
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
