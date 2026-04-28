//
//  MotionDerivedArtifactsFileStore.swift
//  Odoro
//

import Foundation

struct MotionDerivedArtifactsFileStore {
    private let fileManager: FileManager
    private let baseDirectoryURL: URL

    init(fileManager: FileManager = .default, baseDirectoryURL: URL? = nil) {
        self.fileManager = fileManager
        if let baseDirectoryURL {
            self.baseDirectoryURL = baseDirectoryURL
        } else {
            let applicationSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.baseDirectoryURL = applicationSupportURL.appending(path: "ClipArtifacts", directoryHint: .isDirectory)
        }
    }

    func artifactsURL(for takeID: UUID) -> URL {
        baseDirectoryURL.appending(path: "\(takeID.uuidString).odoro.artifacts", directoryHint: .notDirectory)
    }

    @discardableResult
    func write(_ artifacts: MotionDerivedArtifacts?, for takeID: UUID) throws -> URL? {
        guard let artifacts else {
            return nil
        }

        try ensureBaseDirectoryExists()
        let artifactsURL = artifactsURL(for: takeID)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(artifacts)
        try data.write(to: artifactsURL, options: .atomic)
        return artifactsURL
    }

    func read(for takeID: UUID) throws -> MotionDerivedArtifacts? {
        let artifactsURL = artifactsURL(for: takeID)
        guard fileManager.fileExists(atPath: artifactsURL.path()) else {
            return nil
        }

        let decoder = JSONDecoder()
        let data = try Data(contentsOf: artifactsURL)
        return try decoder.decode(MotionDerivedArtifacts.self, from: data)
    }

    func removeArtifacts(for takeID: UUID) throws {
        let artifactsURL = artifactsURL(for: takeID)
        guard fileManager.fileExists(atPath: artifactsURL.path()) else {
            return
        }

        try fileManager.removeItem(at: artifactsURL)
    }

    private func ensureBaseDirectoryExists() throws {
        guard !fileManager.fileExists(atPath: baseDirectoryURL.path()) else {
            return
        }

        try fileManager.createDirectory(at: baseDirectoryURL, withIntermediateDirectories: true)
    }
}
