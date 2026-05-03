//
//  AppConfiguration.swift
//  Odoro
//

import Foundation

struct AppConfiguration {
    static let current = AppConfiguration(bundle: .main)

    let environmentName: String
    let avatarStorageBaseURL: URL?

    init(bundle: Bundle) {
        environmentName = Self.stringValue(for: "OdoroEnvironment", in: bundle) ?? "prod"
        avatarStorageBaseURL = Self.resolvedAvatarStorageBaseURL(
            from: Self.stringValue(for: "OdoroAvatarStorageBaseURL", in: bundle)
        )
    }

    var remoteAvatarCatalogManifestURL: URL? {
        avatarStorageBaseURL?.appending(path: "catalogs/avatar-catalog.production.json", directoryHint: .notDirectory)
    }

    func remoteAvatarAssetURL(path: String) -> URL? {
        avatarStorageBaseURL?.appending(path: path, directoryHint: .notDirectory)
    }

    func remoteAvatarAssetURLString(path: String) -> String {
        remoteAvatarAssetURL(path: path)?.absoluteString ?? path
    }

    static func resolvedAvatarStorageBaseURL(from rawValue: String?) -> URL? {
        guard let baseURLString = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !baseURLString.isEmpty,
              let parsedURL = URL(string: baseURLString),
              parsedURL.scheme != nil else {
            return nil
        }

        return parsedURL
    }

    private static func stringValue(for key: String, in bundle: Bundle) -> String? {
        bundle.object(forInfoDictionaryKey: key) as? String
    }
}
