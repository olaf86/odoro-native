//
//  AvatarAssetStore.swift
//  Odoro
//

import Foundation

struct AvatarAssetStore {
    typealias RemoteFileDownloader = @Sendable (URL) async throws -> URL
    typealias DownloadableAvatarFallbackProvider = @Sendable (AvatarAssetVariant) throws -> DownloadableAvatarFallback

    struct DownloadableAvatarFallback {
        var runtimeAssetURL: URL
        var rigProfile: AvatarRigProfile
        var displayName: String
    }

    enum StoreError: LocalizedError {
        case unsupportedFileExtension(String)
        case unsupportedRuntimeFormat(AvatarRuntimeFormat)
        case invalidGLBFile
        case missingRemoteAssetURL(String)
        case missingBundledFallbackAsset
        case invalidPackageManifest

        var errorDescription: String? {
            switch self {
            case let .unsupportedFileExtension(ext):
                "Unsupported avatar file type: \(ext)"
            case let .unsupportedRuntimeFormat(format):
                "Unsupported downloadable avatar format: \(format.rawValue)"
            case .invalidGLBFile:
                "The selected GLB file could not be parsed."
            case let .missingRemoteAssetURL(label):
                "Avatar package is missing a remote \(label) URL."
            case .missingBundledFallbackAsset:
                "Avatar package is missing its bundled fallback asset."
            case .invalidPackageManifest:
                "The downloaded avatar package manifest is invalid."
            }
        }
    }

    private let fileManager: FileManager
    private let baseDirectoryURL: URL
    private let remoteFileDownloader: RemoteFileDownloader
    private let downloadableAvatarFallbackProvider: DownloadableAvatarFallbackProvider

    init(
        fileManager: FileManager = .default,
        baseDirectoryURL: URL? = nil,
        remoteFileDownloader: @escaping RemoteFileDownloader = Self.defaultRemoteFileDownloader,
        downloadableAvatarFallbackProvider: DownloadableAvatarFallbackProvider? = nil
    ) {
        self.fileManager = fileManager
        self.remoteFileDownloader = remoteFileDownloader
        self.downloadableAvatarFallbackProvider = downloadableAvatarFallbackProvider
            ?? { try Self.defaultDownloadableAvatarFallbackProvider(for: $0) }
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

    func installDownloadableAvatar(from variant: AvatarAssetVariant) async throws -> StageAvatarOption {
        guard variant.runtimeFormat == .usdz else {
            throw StoreError.unsupportedRuntimeFormat(variant.runtimeFormat)
        }

        try ensureBaseDirectoryExists()

        guard let remoteURLs = Self.remoteAssetURLs(for: variant) else {
            return try installBundledFallbackDownloadableAvatar(from: variant)
        }

        let downloadedPackageManifestURL = try await remoteFileDownloader(remoteURLs.packageManifestURL)
        let downloadedRigProfileURL = try await remoteFileDownloader(remoteURLs.rigProfileURL)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let packageManifestData = try Data(contentsOf: downloadedPackageManifestURL)
        let rigProfileData = try Data(contentsOf: downloadedRigProfileURL)
        let packageManifest = try decoder.decode(AvatarPackageManifest.self, from: packageManifestData)
        let rigDocument = try decoder.decode(
            AvatarRigProfileDocument.self,
            from: rigProfileData
        )

        guard
            packageManifest.avatarID == variant.avatarID,
            packageManifest.variantID == variant.id,
            packageManifest.version == variant.version,
            packageManifest.runtimeFormat == variant.runtimeFormat,
            rigDocument.profile.id == variant.rigProfileID,
            rigDocument.profile.runtimeFormat == variant.runtimeFormat
        else {
            throw StoreError.invalidPackageManifest
        }

        let downloadedRuntimeAssetURL = try await remoteFileDownloader(remoteURLs.runtimeAssetURL)
        return try installPackage(
            variant: variant,
            runtimeAssetSourceURL: downloadedRuntimeAssetURL,
            packageManifest: packageManifest,
            rigProfile: rigDocument.profile,
            packageManifestData: packageManifestData,
            rigProfileData: rigProfileData
        )
    }

    private func installBundledFallbackDownloadableAvatar(from variant: AvatarAssetVariant) throws -> StageAvatarOption {
        let fallback = try downloadableAvatarFallbackProvider(variant)
        let runtimeAssetByteCount = try fileSize(at: fallback.runtimeAssetURL)
        let packageManifest = AvatarPackageManifest(
            schemaVersion: 1,
            avatarID: variant.avatarID,
            variantID: variant.id,
            displayName: fallback.displayName,
            source: .downloadable,
            version: variant.version,
            runtimeFormat: variant.runtimeFormat,
            runtimeAssetFilename: "model.\(variant.runtimeFormat.rawValue)",
            generatedRigProfileID: fallback.rigProfile.id,
            installedAt: .now,
            sourceFilename: fallback.runtimeAssetURL.lastPathComponent,
            sourceFileByteCount: runtimeAssetByteCount,
            detectedNodeNames: detectedNodeNames(for: fallback.rigProfile)
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        return try installPackage(
            variant: variant,
            runtimeAssetSourceURL: fallback.runtimeAssetURL,
            packageManifest: packageManifest,
            rigProfile: fallback.rigProfile,
            packageManifestData: try encoder.encode(packageManifest),
            rigProfileData: try encoder.encode(
                AvatarRigProfileDocument(schemaVersion: 1, profile: fallback.rigProfile)
            )
        )
    }

    private func installPackage(
        variant: AvatarAssetVariant,
        runtimeAssetSourceURL: URL,
        packageManifest: AvatarPackageManifest,
        rigProfile: AvatarRigProfile,
        packageManifestData: Data,
        rigProfileData: Data
    ) throws -> StageAvatarOption {
        let avatarDirectoryURL = baseDirectoryURL.appending(path: variant.avatarID, directoryHint: .isDirectory)
        try fileManager.createDirectory(at: avatarDirectoryURL, withIntermediateDirectories: true)

        let installedVersionDirectoryURL = avatarDirectoryURL.appending(
            path: variant.version,
            directoryHint: .isDirectory
        )
        let stagingDirectoryURL = avatarDirectoryURL.appending(
            path: "\(variant.version).staging-\(UUID().uuidString.lowercased())",
            directoryHint: .isDirectory
        )

        try fileManager.createDirectory(at: stagingDirectoryURL, withIntermediateDirectories: true)

        do {
            let runtimeAssetDestinationURL = stagingDirectoryURL.appending(
                path: packageManifest.runtimeAssetFilename,
                directoryHint: .notDirectory
            )
            let packageManifestDestinationURL = stagingDirectoryURL.appending(
                path: "package_manifest.json",
                directoryHint: .notDirectory
            )
            let rigProfileDestinationURL = stagingDirectoryURL.appending(
                path: "rig_profile.json",
                directoryHint: .notDirectory
            )

            try copyDownloadedFile(
                from: runtimeAssetSourceURL,
                to: runtimeAssetDestinationURL
            )
            try packageManifestData.write(to: packageManifestDestinationURL, options: .atomic)
            try rigProfileData.write(to: rigProfileDestinationURL, options: .atomic)

            if fileManager.fileExists(atPath: installedVersionDirectoryURL.path()) {
                try fileManager.removeItem(at: installedVersionDirectoryURL)
            }

            try fileManager.moveItem(at: stagingDirectoryURL, to: installedVersionDirectoryURL)

            let installedRuntimeAssetURL = installedVersionDirectoryURL.appending(
                path: packageManifest.runtimeAssetFilename,
                directoryHint: .notDirectory
            )

            return makeOption(
                packageManifest: packageManifest,
                rigProfile: rigProfile,
                runtimeAssetURL: installedRuntimeAssetURL
            )
        } catch {
            try? fileManager.removeItem(at: stagingDirectoryURL)
            throw error
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
        let subtitle: String
        let systemImageName: String

        switch packageManifest.source {
        case .localDevelopment:
            subtitle = "Imported from local GLB. Generated rig profile is editable in Application Support."
            systemImageName = "person.crop.square.badge.plus"
        case .downloadable:
            subtitle = "Downloaded avatar package installed locally for stage playback."
            systemImageName = "arrow.down.circle"
        case .bundled:
            subtitle = "Bundled avatar package installed locally for stage playback."
            systemImageName = "shippingbox"
        }

        return StageAvatarOption(
            selection: .avatar(avatarID: packageManifest.avatarID, variantID: packageManifest.variantID),
            title: packageManifest.displayName,
            subtitle: subtitle,
            systemImageName: systemImageName,
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

    private func copyDownloadedFile(from sourceURL: URL, to destinationURL: URL) throws {
        if fileManager.fileExists(atPath: destinationURL.path()) {
            try fileManager.removeItem(at: destinationURL)
        }

        try fileManager.copyItem(at: sourceURL, to: destinationURL)
    }

    private func fileSize(at url: URL) throws -> Int {
        let attributes = try fileManager.attributesOfItem(atPath: url.path())
        return (attributes[.size] as? NSNumber)?.intValue ?? 0
    }

    private func detectedNodeNames(for rigProfile: AvatarRigProfile) -> [String] {
        let names = [rigProfile.rootBoneName] + rigProfile.bindings.flatMap { binding in
            [
                binding.boneName,
                binding.sourceJoint.rawJointName,
                binding.parentSourceJoint?.rawJointName,
            ]
            .compactMap { $0 }
        }
        return Array(Set(names)).sorted()
    }

    nonisolated private static func displayName(from rawName: String) -> String {
        rawName
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { $0.capitalized }
            .joined(separator: " ")
    }

    nonisolated private static func slug(from text: String) -> String {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let scalars = folded.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(String(scalar).lowercased()) : "-"
        }
        let raw = String(scalars)
        let collapsed = raw.replacingOccurrences(of: "-+", with: "-", options: .regularExpression)
        return collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private static func remoteAssetURLs(for variant: AvatarAssetVariant) -> (
        runtimeAssetURL: URL,
        packageManifestURL: URL,
        rigProfileURL: URL
    )? {
        guard
            let runtimeAssetURL = resolvedRemoteURL(from: variant.runtimeAssetRemoteURL),
            let packageManifestURL = resolvedRemoteURL(from: variant.packageManifestRemoteURL),
            let rigProfileURL = resolvedRemoteURL(from: variant.rigProfileRemoteURL)
        else {
            return nil
        }

        return (runtimeAssetURL, packageManifestURL, rigProfileURL)
    }

    private static func resolvedRemoteURL(from remoteURLString: String?) -> URL? {
        guard let remoteURLString,
              let remoteURL = URL(string: remoteURLString),
              remoteURL.scheme != nil else {
            return nil
        }

        return remoteURL
    }

    private static func defaultRemoteFileDownloader(from remoteURL: URL) async throws -> URL {
        let (downloadedFileURL, _) = try await URLSession.shared.download(from: remoteURL)
        return downloadedFileURL
    }

    nonisolated private static func defaultDownloadableAvatarFallbackProvider(
        for variant: AvatarAssetVariant
    ) throws -> DownloadableAvatarFallback {
        guard let runtimeAssetURL = Bundle.main.url(forResource: "robot", withExtension: "usdz") else {
            throw StoreError.missingBundledFallbackAsset
        }

        let displayName = displayName(from: variant.avatarID)
        var rigProfile = AvatarCatalog.robotRigProfile
        rigProfile.id = variant.rigProfileID
        rigProfile.displayName = "\(displayName) Rig"
        rigProfile.runtimeAssetRelativePath = "model.\(variant.runtimeFormat.rawValue)"

        return DownloadableAvatarFallback(
            runtimeAssetURL: runtimeAssetURL,
            rigProfile: rigProfile,
            displayName: displayName
        )
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
        appendBinding(aliases: ["leftupperarm", "leftarm", "luparm", "lupperarm"], canonicalJoint: .leftUpperArm, parentAliases: ["leftshoulder", "lshoulder"], parentJoint: .leftShoulder)
        appendBinding(aliases: ["rightupperarm", "rightarm", "ruparm", "rupperarm"], canonicalJoint: .rightUpperArm, parentAliases: ["rightshoulder", "rshoulder"], parentJoint: .rightShoulder)
        appendBinding(aliases: ["leftlowerarm", "leftforearm", "llowarm", "llowerarm"], canonicalJoint: .leftElbow, parentAliases: ["leftupperarm", "leftarm", "luparm", "lupperarm"], parentJoint: .leftUpperArm)
        appendBinding(aliases: ["rightlowerarm", "rightforearm", "rlowarm", "rlowerarm"], canonicalJoint: .rightElbow, parentAliases: ["rightupperarm", "rightarm", "ruparm", "rupperarm"], parentJoint: .rightUpperArm)
        appendBinding(aliases: ["lefthand", "lhand"], canonicalJoint: .leftWrist, parentAliases: ["leftlowerarm", "leftforearm", "llowarm", "llowerarm"], parentJoint: .leftElbow)
        appendBinding(aliases: ["righthand", "rhand"], canonicalJoint: .rightWrist, parentAliases: ["rightlowerarm", "rightforearm", "rlowarm", "rlowerarm"], parentJoint: .rightElbow)
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
