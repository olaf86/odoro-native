//
//  AvatarModels.swift
//  Odoro
//

import Foundation
import simd

enum AvatarAssetSource: String, Codable, Sendable {
    case bundled
    case downloadable
    case localDevelopment
}

enum AvatarRuntimeFormat: String, Codable, Sendable {
    case usdz
    case usdc
    case glb

    var isUSD: Bool {
        switch self {
        case .usdz, .usdc:
            true
        case .glb:
            false
        }
    }
}

enum AvatarInstallState: String, Codable, Sendable {
    case bundled
    case installed
    case notInstalled
}

enum StageAvatarSelectionKind: String, Codable, Sendable {
    case proceduralSkeleton
    case avatar
}

struct StageAvatarSelection: Codable, Hashable, Identifiable, Sendable {
    var kind: StageAvatarSelectionKind
    var avatarID: String?
    var variantID: String?

    var id: String {
        switch kind {
        case .proceduralSkeleton:
            "procedural-skeleton"
        case .avatar:
            "\(avatarID ?? "avatar")::\(variantID ?? "default")"
        }
    }

    static let proceduralSkeleton = StageAvatarSelection(
        kind: .proceduralSkeleton,
        avatarID: nil,
        variantID: nil
    )

    static func avatar(avatarID: String, variantID: String) -> StageAvatarSelection {
        StageAvatarSelection(kind: .avatar, avatarID: avatarID, variantID: variantID)
    }
}

struct AvatarRigJointReference: Codable, Hashable, Sendable {
    var canonicalJoint: OdoroJointName?
    var rawJointName: String?

    init(canonicalJoint: OdoroJointName? = nil, rawJointName: String? = nil) {
        self.canonicalJoint = canonicalJoint
        self.rawJointName = rawJointName
    }
}

enum AvatarTranslationMode: String, Codable, Sendable {
    case direct
    case bindPose
}

struct AvatarBoneBinding: Codable, Hashable, Identifiable, Sendable {
    var boneName: String
    var sourceJoint: AvatarRigJointReference
    var parentSourceJoint: AvatarRigJointReference?
    var rotationOffset: MotionJointRotation?
    var translationMode: AvatarTranslationMode
    var weight: Float

    var id: String { boneName }

    init(
        boneName: String,
        sourceJoint: AvatarRigJointReference,
        parentSourceJoint: AvatarRigJointReference? = nil,
        rotationOffset: MotionJointRotation? = nil,
        translationMode: AvatarTranslationMode = .direct,
        weight: Float = 1
    ) {
        self.boneName = boneName
        self.sourceJoint = sourceJoint
        self.parentSourceJoint = parentSourceJoint
        self.rotationOffset = rotationOffset
        self.translationMode = translationMode
        self.weight = weight
    }
}

struct AvatarRigProfile: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var displayName: String
    var skeletonId: String
    var sourceFormat: AvatarRuntimeFormat
    var runtimeFormat: AvatarRuntimeFormat
    var runtimeAssetRelativePath: String
    var rootBoneName: String
    var bindings: [AvatarBoneBinding]
    var scaleCompensation: Float
    var floorOffset: Float
    var schemaVersion: Int
}

struct AvatarAssetVariant: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var avatarID: String
    var version: String
    var runtimeFormat: AvatarRuntimeFormat
    var runtimeAssetRelativePath: String
    var runtimeAssetRemoteURL: String?
    var runtimeAssetChecksum: String?
    var runtimeAssetSizeBytes: Int
    var packageManifestRelativePath: String?
    var packageManifestRemoteURL: String?
    var rigProfileID: String
    var rigProfileRelativePath: String?
    var rigProfileRemoteURL: String?
    var minimumAppVersion: String?
    var minimumOSVersion: String?
    var installState: AvatarInstallState

    var hasRemotePackageURLs: Bool {
        [
            runtimeAssetRemoteURL,
            packageManifestRemoteURL,
            rigProfileRemoteURL,
        ]
        .allSatisfy { remoteURLString in
            guard let remoteURLString,
                  let remoteURL = URL(string: remoteURLString),
                  let scheme = remoteURL.scheme,
                  !scheme.isEmpty else {
                return false
            }

            if ["http", "https"].contains(scheme.lowercased()) {
                guard let host = remoteURL.host, !host.isEmpty else {
                    return false
                }
            }

            return true
        }
    }
}

struct AvatarCatalogItem: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var slug: String
    var displayName: String
    var subtitle: String
    var authorName: String
    var systemImageName: String
    var thumbnailURL: String?
    var previewVideoURL: String?
    var defaultRigProfileID: String
    var defaultVariantID: String
    var availableVariants: [AvatarAssetVariant]
    var tags: [String]
    var source: AvatarAssetSource
    var isBundled: Bool
}

struct AvatarCatalogManifest: Codable, Hashable, Sendable {
    var schemaVersion: Int
    var generatedAt: Date
    var avatars: [AvatarCatalogItem]
}

struct AvatarRigProfileDocument: Codable, Hashable, Sendable {
    var schemaVersion: Int
    var profile: AvatarRigProfile
}

enum RobotRigTuning {
    /// Keeps the clavicle motion subtle so arm swing is not over-applied
    /// on top of the upper-arm retargeting.
    nonisolated static let shoulderRotationWeight: Float = 0.35
}

struct AvatarPackageManifest: Codable, Hashable, Sendable {
    var schemaVersion: Int
    var avatarID: String
    var variantID: String
    var displayName: String
    var source: AvatarAssetSource
    var version: String
    var runtimeFormat: AvatarRuntimeFormat
    var runtimeAssetFilename: String
    var generatedRigProfileID: String
    var installedAt: Date
    var sourceFilename: String
    var sourceFileByteCount: Int
    var detectedNodeNames: [String]
}

struct StageAvatarOption: Identifiable, Hashable, Sendable {
    var selection: StageAvatarSelection
    var title: String
    var subtitle: String
    var systemImageName: String
    var source: AvatarAssetSource
    var installState: AvatarInstallState
    var runtimeFormat: AvatarRuntimeFormat?
    var runtimeAssetResourceName: String?
    var runtimeAssetURL: URL?
    var rigProfileID: String?
    var rigProfile: AvatarRigProfile?

    var id: String { selection.id }

    var badgeText: String? {
        if source == .localDevelopment {
            return "Local"
        }

        switch installState {
        case .bundled:
            return "Bundled"
        case .installed:
            return "Installed"
        case .notInstalled:
            return "Download"
        }
    }

    var titleText: String { title }

    var isReadyForPlayback: Bool {
        selection.kind == .proceduralSkeleton || installState != .notInstalled
    }

    func mergedWithInstalledAsset(_ installedOption: StageAvatarOption) -> StageAvatarOption {
        StageAvatarOption(
            selection: selection,
            title: title,
            subtitle: subtitle,
            systemImageName: systemImageName,
            source: source,
            installState: installedOption.installState,
            runtimeFormat: installedOption.runtimeFormat,
            runtimeAssetResourceName: installedOption.runtimeAssetResourceName,
            runtimeAssetURL: installedOption.runtimeAssetURL,
            rigProfileID: installedOption.rigProfileID,
            rigProfile: installedOption.rigProfile
        )
    }
}

enum AvatarCatalog {
    private static let robotAvatarID = "robot-performer"
    private static let robotVariantID = "robot-performer-bundled-v1"
    private static let robotRigProfileID = "robot.performer.v1"
    private static let avatarSampleAAvatarID = "avatar-sample-a"
    private static let avatarSampleAVariantID = "avatar-sample-a-usdc-v1"
    private static let avatarSampleARigProfileID = "avatar-sample-a.v1"
    private static let avatarSampleBAvatarID = "avatar-sample-b"
    private static let avatarSampleBVariantID = "avatar-sample-b-usdc-v1"
    private static let avatarSampleBRigProfileID = "avatar-sample-b.v1"

    private static func robotJointPath(_ components: String...) -> String {
        (["root", "hips_joint"] + components).joined(separator: "/")
    }

    private static func robotSpineJointPath(_ components: String...) -> String {
        (["root", "hips_joint", "spine_1_joint", "spine_2_joint"] + components).joined(separator: "/")
    }

    static let defaultSelection = StageAvatarSelection.avatar(
        avatarID: robotAvatarID,
        variantID: robotVariantID
    )

    static var defaultOption: StageAvatarOption {
        builtInStageOptions.first {
            $0.selection == defaultSelection
        } ?? builtInStageOptions[0]
    }

    private static func gcsURL(path: String) -> String? {
        AppConfiguration.current.remoteAvatarAssetURL(path: path)?.absoluteString
    }

    private static func downloadableUSDVariant(
        avatarID: String,
        variantID: String,
        rigProfileID: String,
        runtimeFormat: AvatarRuntimeFormat,
        sizeBytes: Int
    ) -> AvatarAssetVariant {
        let version = "1.0.0"
        let assetDirectory = "avatars/\(avatarID)/\(version)"
        let runtimeFilename = "model.\(runtimeFormat.rawValue)"

        return AvatarAssetVariant(
            id: variantID,
            avatarID: avatarID,
            version: version,
            runtimeFormat: runtimeFormat,
            runtimeAssetRelativePath: "\(assetDirectory)/\(runtimeFilename)",
            runtimeAssetRemoteURL: gcsURL(path: "\(assetDirectory)/\(runtimeFilename)"),
            runtimeAssetChecksum: nil,
            runtimeAssetSizeBytes: sizeBytes,
            packageManifestRelativePath: "\(assetDirectory)/package_manifest.json",
            packageManifestRemoteURL: gcsURL(path: "\(assetDirectory)/package_manifest.json"),
            rigProfileID: rigProfileID,
            rigProfileRelativePath: "\(assetDirectory)/rig_profile.json",
            rigProfileRemoteURL: gcsURL(path: "\(assetDirectory)/rig_profile.json"),
            minimumAppVersion: nil,
            minimumOSVersion: "26.4",
            installState: .notInstalled
        )
    }

    nonisolated static let robotRigProfile = AvatarRigProfile(
        id: robotRigProfileID,
        displayName: "Robot Performer",
        skeletonId: OdoroSkeletonDefinition.id,
        sourceFormat: .usdz,
        runtimeFormat: .usdz,
        runtimeAssetRelativePath: "robot.usdz",
        rootBoneName: robotJointPath(),
        bindings: [
            AvatarBoneBinding(
                boneName: robotSpineJointPath(),
                sourceJoint: .init(canonicalJoint: .root, rawJointName: "spine_2_joint"),
                parentSourceJoint: .init(canonicalJoint: .root, rawJointName: "spine_1_joint")
            ),
            AvatarBoneBinding(
                boneName: robotSpineJointPath("spine_3_joint", "spine_4_joint", "spine_5_joint"),
                sourceJoint: .init(canonicalJoint: .root, rawJointName: "spine_5_joint"),
                parentSourceJoint: .init(canonicalJoint: .root, rawJointName: "spine_4_joint")
            ),
            AvatarBoneBinding(
                boneName: robotJointPath(),
                sourceJoint: .init(canonicalJoint: .root, rawJointName: "hips_joint")
            ),
            AvatarBoneBinding(
                boneName: robotSpineJointPath("spine_3_joint", "spine_4_joint", "spine_5_joint", "spine_6_joint"),
                sourceJoint: .init(canonicalJoint: .root, rawJointName: "spine_6_joint"),
                parentSourceJoint: .init(canonicalJoint: .root, rawJointName: "spine_5_joint")
            ),
            AvatarBoneBinding(
                boneName: robotSpineJointPath("spine_3_joint", "spine_4_joint", "spine_5_joint", "spine_6_joint", "spine_7_joint", "neck_1_joint", "neck_2_joint", "neck_3_joint", "neck_4_joint", "head_joint"),
                sourceJoint: .init(canonicalJoint: .head, rawJointName: "head_joint"),
                parentSourceJoint: .init(canonicalJoint: .head, rawJointName: "neck_4_joint")
            ),
            AvatarBoneBinding(
                boneName: robotJointPath("spine_1_joint"),
                sourceJoint: .init(canonicalJoint: .root, rawJointName: "spine_1_joint"),
                parentSourceJoint: .init(canonicalJoint: .root, rawJointName: "hips_joint")
            ),
            AvatarBoneBinding(
                boneName: robotSpineJointPath("spine_3_joint", "spine_4_joint"),
                sourceJoint: .init(canonicalJoint: .root, rawJointName: "spine_4_joint"),
                parentSourceJoint: .init(canonicalJoint: .root, rawJointName: "spine_3_joint")
            ),
            AvatarBoneBinding(
                boneName: robotSpineJointPath("spine_3_joint", "spine_4_joint", "spine_5_joint", "spine_6_joint", "spine_7_joint", "neck_1_joint", "neck_2_joint"),
                sourceJoint: .init(canonicalJoint: .head, rawJointName: "neck_2_joint"),
                parentSourceJoint: .init(canonicalJoint: .head, rawJointName: "neck_1_joint")
            ),
            AvatarBoneBinding(
                boneName: robotJointPath("left_upLeg_joint", "left_leg_joint"),
                sourceJoint: .init(canonicalJoint: .leftKnee, rawJointName: "left_leg_joint"),
                parentSourceJoint: .init(canonicalJoint: .leftHip, rawJointName: "left_upLeg_joint")
            ),
            AvatarBoneBinding(
                boneName: robotJointPath("left_upLeg_joint", "left_leg_joint", "left_foot_joint"),
                sourceJoint: .init(canonicalJoint: .leftFoot, rawJointName: "left_foot_joint"),
                parentSourceJoint: .init(canonicalJoint: .leftKnee, rawJointName: "left_leg_joint")
            ),
            AvatarBoneBinding(
                boneName: robotSpineJointPath("spine_3_joint", "spine_4_joint", "spine_5_joint", "spine_6_joint", "spine_7_joint", "left_shoulder_1_joint", "left_arm_joint"),
                sourceJoint: .init(canonicalJoint: .leftUpperArm, rawJointName: "left_arm_joint"),
                parentSourceJoint: .init(canonicalJoint: .leftShoulder, rawJointName: "left_shoulder_1_joint")
            ),
            AvatarBoneBinding(
                boneName: robotSpineJointPath("spine_3_joint", "spine_4_joint", "spine_5_joint", "spine_6_joint", "spine_7_joint", "left_shoulder_1_joint", "left_arm_joint", "left_forearm_joint"),
                sourceJoint: .init(canonicalJoint: .leftElbow, rawJointName: "left_forearm_joint"),
                parentSourceJoint: .init(canonicalJoint: .leftUpperArm, rawJointName: "left_arm_joint")
            ),
            AvatarBoneBinding(
                boneName: robotJointPath("left_upLeg_joint"),
                sourceJoint: .init(canonicalJoint: .leftHip, rawJointName: "left_upLeg_joint"),
                parentSourceJoint: .init(canonicalJoint: .root, rawJointName: "hips_joint")
            ),
            AvatarBoneBinding(
                boneName: robotSpineJointPath("spine_3_joint", "spine_4_joint", "spine_5_joint", "spine_6_joint", "spine_7_joint", "left_shoulder_1_joint", "left_arm_joint", "left_forearm_joint", "left_hand_joint"),
                sourceJoint: .init(canonicalJoint: .leftWrist, rawJointName: "left_hand_joint"),
                parentSourceJoint: .init(canonicalJoint: .leftWrist, rawJointName: "left_forearm_joint")
            ),
            AvatarBoneBinding(
                boneName: robotSpineJointPath("spine_3_joint", "spine_4_joint", "spine_5_joint", "spine_6_joint", "spine_7_joint", "left_shoulder_1_joint"),
                sourceJoint: .init(canonicalJoint: .leftShoulder, rawJointName: "left_shoulder_1_joint"),
                parentSourceJoint: .init(canonicalJoint: .root, rawJointName: "spine_7_joint"),
                weight: RobotRigTuning.shoulderRotationWeight
            ),
            AvatarBoneBinding(
                boneName: robotSpineJointPath("spine_3_joint", "spine_4_joint", "spine_5_joint", "spine_6_joint", "spine_7_joint", "neck_1_joint", "neck_2_joint", "neck_3_joint"),
                sourceJoint: .init(canonicalJoint: .head, rawJointName: "neck_3_joint"),
                parentSourceJoint: .init(canonicalJoint: .head, rawJointName: "neck_2_joint")
            ),
            AvatarBoneBinding(
                boneName: robotSpineJointPath("spine_3_joint", "spine_4_joint", "spine_5_joint", "spine_6_joint", "spine_7_joint", "neck_1_joint", "neck_2_joint", "neck_3_joint", "neck_4_joint"),
                sourceJoint: .init(canonicalJoint: .head, rawJointName: "neck_4_joint"),
                parentSourceJoint: .init(canonicalJoint: .head, rawJointName: "neck_3_joint")
            ),
            AvatarBoneBinding(
                boneName: robotJointPath("right_upLeg_joint", "right_leg_joint"),
                sourceJoint: .init(canonicalJoint: .rightKnee, rawJointName: "right_leg_joint"),
                parentSourceJoint: .init(canonicalJoint: .rightHip, rawJointName: "right_upLeg_joint")
            ),
            AvatarBoneBinding(
                boneName: robotJointPath("right_upLeg_joint", "right_leg_joint", "right_foot_joint"),
                sourceJoint: .init(canonicalJoint: .rightFoot, rawJointName: "right_foot_joint"),
                parentSourceJoint: .init(canonicalJoint: .rightKnee, rawJointName: "right_leg_joint")
            ),
            AvatarBoneBinding(
                boneName: robotSpineJointPath("spine_3_joint", "spine_4_joint", "spine_5_joint", "spine_6_joint", "spine_7_joint", "right_shoulder_1_joint", "right_arm_joint"),
                sourceJoint: .init(canonicalJoint: .rightUpperArm, rawJointName: "right_arm_joint"),
                parentSourceJoint: .init(canonicalJoint: .rightShoulder, rawJointName: "right_shoulder_1_joint")
            ),
            AvatarBoneBinding(
                boneName: robotSpineJointPath("spine_3_joint", "spine_4_joint", "spine_5_joint", "spine_6_joint", "spine_7_joint", "right_shoulder_1_joint", "right_arm_joint", "right_forearm_joint"),
                sourceJoint: .init(canonicalJoint: .rightElbow, rawJointName: "right_forearm_joint"),
                parentSourceJoint: .init(canonicalJoint: .rightUpperArm, rawJointName: "right_arm_joint")
            ),
            AvatarBoneBinding(
                boneName: robotJointPath("right_upLeg_joint"),
                sourceJoint: .init(canonicalJoint: .rightHip, rawJointName: "right_upLeg_joint"),
                parentSourceJoint: .init(canonicalJoint: .root, rawJointName: "hips_joint")
            ),
            AvatarBoneBinding(
                boneName: robotSpineJointPath("spine_3_joint", "spine_4_joint", "spine_5_joint", "spine_6_joint", "spine_7_joint", "right_shoulder_1_joint", "right_arm_joint", "right_forearm_joint", "right_hand_joint"),
                sourceJoint: .init(canonicalJoint: .rightWrist, rawJointName: "right_hand_joint"),
                parentSourceJoint: .init(canonicalJoint: .rightWrist, rawJointName: "right_forearm_joint")
            ),
            AvatarBoneBinding(
                boneName: robotSpineJointPath("spine_3_joint", "spine_4_joint", "spine_5_joint", "spine_6_joint", "spine_7_joint", "right_shoulder_1_joint"),
                sourceJoint: .init(canonicalJoint: .rightShoulder, rawJointName: "right_shoulder_1_joint"),
                parentSourceJoint: .init(canonicalJoint: .root, rawJointName: "spine_7_joint"),
                weight: RobotRigTuning.shoulderRotationWeight
            ),
        ].map { binding in
            guard binding.boneName != robotJointPath() else {
                return binding
            }

            var binding = binding
            binding.translationMode = .bindPose
            return binding
        },
        scaleCompensation: 1,
        floorOffset: 0.977,
        schemaVersion: 1
    )

    static let manifest = AvatarCatalogManifest(
        schemaVersion: 1,
        generatedAt: Date(timeIntervalSince1970: 1_776_556_800),
        avatars: [
            AvatarCatalogItem(
                id: robotAvatarID,
                slug: robotAvatarID,
                displayName: "Robot Performer",
                subtitle: "Bundled USDZ avatar that is always ready for stage playback.",
                authorName: "Odoro",
                systemImageName: "figure.dance",
                thumbnailURL: nil,
                previewVideoURL: nil,
                defaultRigProfileID: robotRigProfileID,
                defaultVariantID: robotVariantID,
                availableVariants: [
                    AvatarAssetVariant(
                        id: robotVariantID,
                        avatarID: robotAvatarID,
                        version: "1.0.0",
                        runtimeFormat: .usdz,
                        runtimeAssetRelativePath: "robot.usdz",
                        runtimeAssetRemoteURL: nil,
                        runtimeAssetChecksum: nil,
                        runtimeAssetSizeBytes: 0,
                        packageManifestRelativePath: nil,
                        packageManifestRemoteURL: nil,
                        rigProfileID: robotRigProfileID,
                        rigProfileRelativePath: "rigs/robot.performer.v1.json",
                        rigProfileRemoteURL: nil,
                        minimumAppVersion: nil,
                        minimumOSVersion: "26.4",
                        installState: .bundled
                    )
                ],
                tags: ["bundled", "fallback", "usdz"],
                source: .bundled,
                isBundled: true
            ),
            AvatarCatalogItem(
                id: avatarSampleAAvatarID,
                slug: avatarSampleAAvatarID,
                displayName: "Avatar Sample A",
                subtitle: "Download-on-demand USDC avatar package served from GCS.",
                authorName: "Odoro",
                systemImageName: "person.crop.square",
                thumbnailURL: nil,
                previewVideoURL: nil,
                defaultRigProfileID: avatarSampleARigProfileID,
                defaultVariantID: avatarSampleAVariantID,
                availableVariants: [
                    downloadableUSDVariant(
                        avatarID: avatarSampleAAvatarID,
                        variantID: avatarSampleAVariantID,
                        rigProfileID: avatarSampleARigProfileID,
                        runtimeFormat: .usdc,
                        sizeBytes: 26_781_812
                    )
                ],
                tags: ["download", "vroid", "usdc", "gcs"],
                source: .downloadable,
                isBundled: false
            ),
            AvatarCatalogItem(
                id: avatarSampleBAvatarID,
                slug: avatarSampleBAvatarID,
                displayName: "Avatar Sample B",
                subtitle: "Second download-on-demand USDC avatar package served from GCS.",
                authorName: "Odoro",
                systemImageName: "sparkles",
                thumbnailURL: nil,
                previewVideoURL: nil,
                defaultRigProfileID: avatarSampleBRigProfileID,
                defaultVariantID: avatarSampleBVariantID,
                availableVariants: [
                    downloadableUSDVariant(
                        avatarID: avatarSampleBAvatarID,
                        variantID: avatarSampleBVariantID,
                        rigProfileID: avatarSampleBRigProfileID,
                        runtimeFormat: .usdc,
                        sizeBytes: 28_333_772
                    )
                ],
                tags: ["download", "vroid", "usdc", "gcs"],
                source: .downloadable,
                isBundled: false
            ),
        ]
    )

    static let builtInStageOptions: [StageAvatarOption] = [
        StageAvatarOption(
            selection: .proceduralSkeleton,
            title: "Skeleton Preview",
            subtitle: "Use the lightweight joint preview for motion checking.",
            systemImageName: "figure.stand.line.dotted.figure.stand",
            source: .bundled,
            installState: .bundled,
            runtimeFormat: nil,
            runtimeAssetResourceName: nil,
            runtimeAssetURL: nil,
            rigProfileID: nil,
            rigProfile: nil
        )
    ] + manifest.avatars.map { item in
        let variant = item.availableVariants.first { $0.id == item.defaultVariantID } ?? item.availableVariants[0]
        return StageAvatarOption(
            selection: .avatar(avatarID: item.id, variantID: variant.id),
            title: item.displayName,
            subtitle: item.subtitle,
            systemImageName: item.systemImageName,
            source: item.source,
            installState: variant.installState,
            runtimeFormat: variant.runtimeFormat,
            runtimeAssetResourceName: item.source == .bundled ? "robot.\(variant.runtimeFormat.rawValue)" : nil,
            runtimeAssetURL: nil,
            rigProfileID: variant.rigProfileID,
            rigProfile: variant.rigProfileID == robotRigProfileID ? robotRigProfile : nil
        )
    }

    static func variant(for selection: StageAvatarSelection) -> AvatarAssetVariant? {
        guard
            selection.kind == .avatar,
            let avatarID = selection.avatarID,
            let variantID = selection.variantID,
            let item = manifest.avatars.first(where: { $0.id == avatarID })
        else {
            return nil
        }

        return item.availableVariants.first(where: { $0.id == variantID })
    }

    static func stageOptions(installedOptions: [StageAvatarOption]) -> [StageAvatarOption] {
        let baseOptions = builtInStageOptions
        let installedBySelection = Dictionary(uniqueKeysWithValues: installedOptions.map { ($0.selection, $0) })
        let mergedBaseOptions = baseOptions.map { option in
            guard let installedOption = installedBySelection[option.selection] else {
                return option
            }

            return option.mergedWithInstalledAsset(installedOption)
        }
        let additionalOptions = installedOptions.filter { option in
            !baseOptions.contains(where: { $0.selection == option.selection })
        }

        return mergedBaseOptions + additionalOptions
    }
}
