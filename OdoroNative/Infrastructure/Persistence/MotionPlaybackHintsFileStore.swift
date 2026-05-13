//
//  MotionPlaybackHintsFileStore.swift
//  Odoro
//

import Foundation

struct MotionPlaybackHintsFileStore {
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

    func hintsURL(for takeID: UUID) -> URL {
        baseDirectoryURL.appending(path: "\(takeID.uuidString).odoro.hints", directoryHint: .notDirectory)
    }

    @discardableResult
    func write(_ hints: MotionPlaybackHints?, for takeID: UUID) throws -> URL? {
        guard let hints else {
            return nil
        }

        try ensureBaseDirectoryExists()
        let hintsURL = hintsURL(for: takeID)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(hints)
        try data.write(to: hintsURL, options: .atomic)
        return hintsURL
    }

    func read(for takeID: UUID) throws -> MotionPlaybackHints? {
        let hintsURL = hintsURL(for: takeID)
        guard fileManager.fileExists(atPath: hintsURL.path()) else {
            return nil
        }

        let decoder = JSONDecoder()
        let data = try Data(contentsOf: hintsURL)
        return try decoder.decode(MotionPlaybackHints.self, from: data)
    }

    func removeHints(for takeID: UUID) throws {
        let hintsURL = hintsURL(for: takeID)
        guard fileManager.fileExists(atPath: hintsURL.path()) else {
            return
        }

        try fileManager.removeItem(at: hintsURL)
    }

    private func ensureBaseDirectoryExists() throws {
        guard !fileManager.fileExists(atPath: baseDirectoryURL.path()) else {
            return
        }

        try fileManager.createDirectory(at: baseDirectoryURL, withIntermediateDirectories: true)
    }
}
