//
//  AvatarAssetStore.swift
//  Odoro
//

import Foundation

struct AvatarAssetStore {
    enum StoreError: LocalizedError {
        case unsupportedFileExtension(String)
        case invalidGLBFile

        var errorDescription: String? {
            switch self {
            case let .unsupportedFileExtension(ext):
                "Unsupported avatar file type: \(ext)"
            case .invalidGLBFile:
                "The selected GLB file could not be parsed."
            }
        }
    }

    private let fileManager: FileManager
    private let baseDirectoryURL: URL

    init(fileManager: FileManager = .default, baseDirectoryURL: URL? = nil) {
        self.fileManager = fileManager
        if let baseDirectoryURL {
            self.baseDirectoryURL = baseDirectoryURL
        } else {
            let applicationSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.baseDirectoryURL = applicationSupportURL.appending(path: "AvatarAssets", directoryHint: .isDirectory)
        }
    }

    func fetchInstalledAvatarOptions() -> [StageAvatarOption] {
        do {
            try ensureBaseDirectoryExists()

            let packageDirectories = try fileManager.contentsOfDirectory(
                at: baseDirectoryURL,
                includingPropertiesForKeys: nil
            )

            return try packageDirectories
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
                .compactMap(loadOption(fromAvatarDirectory:))
        } catch {
            return []
        }
    }

    func installDevelopmentAvatar(from sourceURL: URL) throws -> StageAvatarOption {
        let fileExtension = sourceURL.pathExtension.lowercased()
        guard fileExtension == AvatarRuntimeFormat.glb.rawValue else {
            throw StoreError.unsupportedFileExtension(fileExtension)
        }

        try ensureBaseDirectoryExists()

        let sourceData = try Data(contentsOf: sourceURL)
        let detectedNodeNames = try GLBNodeNameReader.readNodeNames(from: sourceData)
        let displayName = Self.displayName(from: sourceURL.deletingPathExtension().lastPathComponent)
        let avatarID = "\(Self.slug(from: displayName))-\(UUID().uuidString.prefix(8).lowercased())"
        let version = "local-dev-1"
        let variantID = "\(avatarID)-\(fileExtension)-\(version)"
        let rigProfileID = "\(avatarID).rig.v1"
        let avatarDirectoryURL = baseDirectoryURL.appending(path: avatarID, directoryHint: .isDirectory)
        let versionDirectoryURL = avatarDirectoryURL.appending(path: version, directoryHint: .isDirectory)

        try fileManager.createDirectory(at: versionDirectoryURL, withIntermediateDirectories: true)

        let runtimeFilename = "model.\(fileExtension)"
        let runtimeAssetURL = versionDirectoryURL.appending(path: runtimeFilename, directoryHint: .notDirectory)
        try sourceData.write(to: runtimeAssetURL, options: .atomic)

        let rigProfile = Self.makeGeneratedRigProfile(
            displayName: displayName,
            profileID: rigProfileID,
            runtimeFilename: runtimeFilename,
            detectedNodeNames: detectedNodeNames
        )

        let packageManifest = AvatarPackageManifest(
            schemaVersion: 1,
            avatarID: avatarID,
            variantID: variantID,
            displayName: displayName,
            source: .localDevelopment,
            version: version,
            runtimeFormat: .glb,
            runtimeAssetFilename: runtimeFilename,
            generatedRigProfileID: rigProfileID,
            installedAt: .now,
            sourceFilename: sourceURL.lastPathComponent,
            sourceFileByteCount: sourceData.count,
            detectedNodeNames: detectedNodeNames
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let manifestURL = versionDirectoryURL.appending(path: "package_manifest.json", directoryHint: .notDirectory)
        try encoder.encode(packageManifest).write(to: manifestURL, options: .atomic)

        let rigDocument = AvatarRigProfileDocument(schemaVersion: 1, profile: rigProfile)
        let rigProfileURL = versionDirectoryURL.appending(path: "rig_profile.json", directoryHint: .notDirectory)
        try encoder.encode(rigDocument).write(to: rigProfileURL, options: .atomic)

        return makeOption(
            packageManifest: packageManifest,
            rigProfile: rigProfile,
            runtimeAssetURL: runtimeAssetURL
        )
    }

    private func loadOption(fromAvatarDirectory avatarDirectoryURL: URL) throws -> StageAvatarOption? {
        let versionDirectories = try fileManager.contentsOfDirectory(
            at: avatarDirectoryURL,
            includingPropertiesForKeys: nil
        )
        .filter { $0.hasDirectoryPath }
        .sorted { $0.lastPathComponent > $1.lastPathComponent }

        guard let versionDirectoryURL = versionDirectories.first else {
            return nil
        }

        let manifestURL = versionDirectoryURL.appending(path: "package_manifest.json", directoryHint: .notDirectory)
        let rigProfileURL = versionDirectoryURL.appending(path: "rig_profile.json", directoryHint: .notDirectory)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let packageManifest = try decoder.decode(AvatarPackageManifest.self, from: Data(contentsOf: manifestURL))
        let rigDocument = try decoder.decode(AvatarRigProfileDocument.self, from: Data(contentsOf: rigProfileURL))
        let runtimeAssetURL = versionDirectoryURL.appending(path: packageManifest.runtimeAssetFilename, directoryHint: .notDirectory)

        return makeOption(
            packageManifest: packageManifest,
            rigProfile: rigDocument.profile,
            runtimeAssetURL: runtimeAssetURL
        )
    }

    private func makeOption(
        packageManifest: AvatarPackageManifest,
        rigProfile: AvatarRigProfile,
        runtimeAssetURL: URL
    ) -> StageAvatarOption {
        StageAvatarOption(
            selection: .avatar(avatarID: packageManifest.avatarID, variantID: packageManifest.variantID),
            title: packageManifest.displayName,
            subtitle: "Imported from local GLB. Generated rig profile is editable in Application Support.",
            systemImageName: "person.crop.square.badge.plus",
            source: packageManifest.source,
            installState: .installed,
            runtimeFormat: packageManifest.runtimeFormat,
            runtimeAssetResourceName: nil,
            runtimeAssetURL: runtimeAssetURL,
            rigProfileID: packageManifest.generatedRigProfileID,
            rigProfile: rigProfile
        )
    }

    private func ensureBaseDirectoryExists() throws {
        guard !fileManager.fileExists(atPath: baseDirectoryURL.path()) else {
            return
        }

        try fileManager.createDirectory(at: baseDirectoryURL, withIntermediateDirectories: true)
    }

    private static func displayName(from rawName: String) -> String {
        rawName
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { $0.capitalized }
            .joined(separator: " ")
    }

    private static func slug(from text: String) -> String {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let scalars = folded.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(String(scalar).lowercased()) : "-"
        }
        let raw = String(scalars)
        let collapsed = raw.replacingOccurrences(of: "-+", with: "-", options: .regularExpression)
        return collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private static func makeGeneratedRigProfile(
        displayName: String,
        profileID: String,
        runtimeFilename: String,
        detectedNodeNames: [String]
    ) -> AvatarRigProfile {
        let resolver = AvatarBoneNameResolver(nodeNames: detectedNodeNames)

        var bindings: [AvatarBoneBinding] = []

        func appendBinding(
            aliases: [String],
            canonicalJoint: OdoroJointName,
            parentAliases: [String]? = nil,
            parentJoint: OdoroJointName? = nil
        ) {
            guard let boneName = resolver.firstMatch(for: aliases) else {
                return
            }

            let parentReference: AvatarRigJointReference?
            if let parentAliases, let parentBoneName = resolver.firstMatch(for: parentAliases) {
                parentReference = AvatarRigJointReference(canonicalJoint: parentJoint, rawJointName: parentBoneName)
            } else {
                parentReference = parentJoint.map { AvatarRigJointReference(canonicalJoint: $0) }
            }

            bindings.append(
                AvatarBoneBinding(
                    boneName: boneName,
                    sourceJoint: AvatarRigJointReference(canonicalJoint: canonicalJoint),
                    parentSourceJoint: parentReference
                )
            )
        }

        appendBinding(aliases: ["hips", "pelvis"], canonicalJoint: .root)
        appendBinding(aliases: ["spine", "spine1", "chest", "upperchest"], canonicalJoint: .root, parentAliases: ["hips", "pelvis"], parentJoint: .root)
        appendBinding(aliases: ["neck"], canonicalJoint: .head, parentAliases: ["spine", "spine1", "chest", "upperchest"], parentJoint: .root)
        appendBinding(aliases: ["head"], canonicalJoint: .head, parentAliases: ["neck"], parentJoint: .head)
        appendBinding(aliases: ["leftshoulder", "lshoulder"], canonicalJoint: .leftShoulder, parentAliases: ["spine", "spine1", "chest", "upperchest"], parentJoint: .root)
        appendBinding(aliases: ["rightshoulder", "rshoulder"], canonicalJoint: .rightShoulder, parentAliases: ["spine", "spine1", "chest", "upperchest"], parentJoint: .root)
        appendBinding(aliases: ["leftupperarm", "leftarm", "luparm", "lupperarm"], canonicalJoint: .leftElbow, parentAliases: ["leftshoulder", "lshoulder"], parentJoint: .leftShoulder)
        appendBinding(aliases: ["rightupperarm", "rightarm", "ruparm", "rupperarm"], canonicalJoint: .rightElbow, parentAliases: ["rightshoulder", "rshoulder"], parentJoint: .rightShoulder)
        appendBinding(aliases: ["leftlowerarm", "leftforearm", "llowarm", "llowerarm"], canonicalJoint: .leftWrist, parentAliases: ["leftupperarm", "leftarm", "luparm", "lupperarm"], parentJoint: .leftElbow)
        appendBinding(aliases: ["rightlowerarm", "rightforearm", "rlowarm", "rlowerarm"], canonicalJoint: .rightWrist, parentAliases: ["rightupperarm", "rightarm", "ruparm", "rupperarm"], parentJoint: .rightElbow)
        appendBinding(aliases: ["lefthand", "lhand"], canonicalJoint: .leftWrist, parentAliases: ["leftlowerarm", "leftforearm", "llowarm", "llowerarm"], parentJoint: .leftWrist)
        appendBinding(aliases: ["righthand", "rhand"], canonicalJoint: .rightWrist, parentAliases: ["rightlowerarm", "rightforearm", "rlowarm", "rlowerarm"], parentJoint: .rightWrist)
        appendBinding(aliases: ["leftupperleg", "leftupleg", "leftthigh", "lupperleg"], canonicalJoint: .leftHip, parentAliases: ["hips", "pelvis"], parentJoint: .root)
        appendBinding(aliases: ["rightupperleg", "rightupleg", "rightthigh", "rupperleg"], canonicalJoint: .rightHip, parentAliases: ["hips", "pelvis"], parentJoint: .root)
        appendBinding(aliases: ["leftlowerleg", "leftleg", "leftcalf", "llowerleg"], canonicalJoint: .leftKnee, parentAliases: ["leftupperleg", "leftupleg", "leftthigh", "lupperleg"], parentJoint: .leftHip)
        appendBinding(aliases: ["rightlowerleg", "rightleg", "rightcalf", "rlowerleg"], canonicalJoint: .rightKnee, parentAliases: ["rightupperleg", "rightupleg", "rightthigh", "rupperleg"], parentJoint: .rightHip)
        appendBinding(aliases: ["leftfoot", "leftankle", "lfoot"], canonicalJoint: .leftFoot, parentAliases: ["leftlowerleg", "leftleg", "leftcalf", "llowerleg"], parentJoint: .leftKnee)
        appendBinding(aliases: ["rightfoot", "rightankle", "rfoot"], canonicalJoint: .rightFoot, parentAliases: ["rightlowerleg", "rightleg", "rightcalf", "rlowerleg"], parentJoint: .rightKnee)

        let rootBoneName = resolver.firstMatch(for: ["hips", "pelvis"]) ?? "Hips"

        return AvatarRigProfile(
            id: profileID,
            displayName: "\(displayName) Rig",
            skeletonId: OdoroSkeletonDefinition.id,
            sourceFormat: .glb,
            runtimeFormat: .glb,
            runtimeAssetRelativePath: runtimeFilename,
            rootBoneName: rootBoneName,
            bindings: bindings,
            scaleCompensation: 1,
            floorOffset: 0,
            schemaVersion: 1
        )
    }
}

private struct AvatarBoneNameResolver {
    private let nodeNames: [String]
    private let normalizedNodeNames: [String]

    init(nodeNames: [String]) {
        self.nodeNames = nodeNames
        self.normalizedNodeNames = nodeNames.map(Self.normalize)
    }

    func firstMatch(for aliases: [String]) -> String? {
        let normalizedAliases = aliases.map(Self.normalize)

        for (index, normalizedNodeName) in normalizedNodeNames.enumerated() {
            if normalizedAliases.contains(where: { normalizedNodeName == $0 || normalizedNodeName.contains($0) }) {
                return nodeNames[index]
            }
        }

        return nil
    }

    nonisolated private static func normalize(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init)
            .joined()
            .lowercased()
    }
}

private enum GLBNodeNameReader {
    private static let jsonChunkType: UInt32 = 0x4E4F534A

    static func readNodeNames(from data: Data) throws -> [String] {
        guard data.count >= 20 else {
            throw AvatarAssetStore.StoreError.invalidGLBFile
        }

        let magic = data.readUInt32(at: 0)
        guard magic == 0x46546C67 else {
            throw AvatarAssetStore.StoreError.invalidGLBFile
        }

        var offset = 12
        while offset + 8 <= data.count {
            let chunkLength = Int(data.readUInt32(at: offset))
            let chunkType = data.readUInt32(at: offset + 4)
            offset += 8

            guard offset + chunkLength <= data.count else {
                throw AvatarAssetStore.StoreError.invalidGLBFile
            }

            if chunkType == jsonChunkType {
                let chunkData = data.subdata(in: offset..<(offset + chunkLength))
                let jsonObject = try JSONSerialization.jsonObject(with: chunkData)
                guard let json = jsonObject as? [String: Any],
                      let nodes = json["nodes"] as? [[String: Any]] else {
                    return []
                }

                return nodes.compactMap { $0["name"] as? String }
            }

            offset += chunkLength
        }

        throw AvatarAssetStore.StoreError.invalidGLBFile
    }
}

private extension Data {
    func readUInt32(at offset: Int) -> UInt32 {
        subdata(in: offset..<(offset + 4)).withUnsafeBytes { rawBuffer in
            rawBuffer.load(as: UInt32.self)
        }.littleEndian
    }
}
