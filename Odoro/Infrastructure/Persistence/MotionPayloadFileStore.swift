//
//  MotionPayloadFileStore.swift
//  Odoro
//

import Foundation

struct MotionPayloadFileStore {
    private let fileManager: FileManager
    private let baseDirectoryURL: URL

    init(fileManager: FileManager = .default, baseDirectoryURL: URL? = nil) {
        self.fileManager = fileManager
        if let baseDirectoryURL {
            self.baseDirectoryURL = baseDirectoryURL
        } else {
            let applicationSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.baseDirectoryURL = applicationSupportURL.appending(path: "Clips", directoryHint: .isDirectory)
        }
    }

    func payloadURL(for takeID: UUID) -> URL {
        baseDirectoryURL.appending(path: "\(takeID.uuidString).odoro", directoryHint: .notDirectory)
    }

    func write(_ payload: MotionPayload, for takeID: UUID) throws -> URL {
        try ensureBaseDirectoryExists()
        let payloadURL = payloadURL(for: takeID)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(payload)
        try data.write(to: payloadURL, options: .atomic)
        return payloadURL
    }

    func read(from payloadURL: URL) throws -> MotionPayload {
        let decoder = JSONDecoder()
        let data = try Data(contentsOf: payloadURL)
        return try decoder.decode(MotionPayload.self, from: data)
    }

    func removePayload(for takeID: UUID) throws {
        let payloadURL = payloadURL(for: takeID)
        guard fileManager.fileExists(atPath: payloadURL.path()) else {
            return
        }
        try fileManager.removeItem(at: payloadURL)
    }

    private func ensureBaseDirectoryExists() throws {
        guard !fileManager.fileExists(atPath: baseDirectoryURL.path()) else {
            return
        }

        try fileManager.createDirectory(at: baseDirectoryURL, withIntermediateDirectories: true)
    }
}
