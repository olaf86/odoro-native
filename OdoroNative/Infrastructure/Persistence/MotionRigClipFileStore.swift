//
//  MotionRigClipFileStore.swift
//  Odoro
//

import Foundation

struct MotionRigClipFileStore {
    private let fileManager: FileManager
    private let baseDirectoryURL: URL

    init(fileManager: FileManager = .default, baseDirectoryURL: URL? = nil) {
        self.fileManager = fileManager
        if let baseDirectoryURL {
            self.baseDirectoryURL = baseDirectoryURL
        } else {
            let applicationSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.baseDirectoryURL = applicationSupportURL.appending(path: "RigClips", directoryHint: .isDirectory)
        }
    }

    func rigClipURL(for takeID: UUID) -> URL {
        baseDirectoryURL.appending(path: "\(takeID.uuidString).odoro.rig", directoryHint: .notDirectory)
    }

    @discardableResult
    func write(
        _ clip: MotionClip?,
        for takeID: UUID,
        captureMode: CaptureMode,
        recordingContext: MotionRecordingContext
    ) throws -> URL? {
        guard let clip else {
            return nil
        }

        try ensureBaseDirectoryExists()
        let rigClipURL = rigClipURL(for: takeID)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let payload = MotionPayload(
            clip: clip,
            clipIsCanonical: true,
            captureMode: captureMode,
            recordingContext: recordingContext,
            sourcePlatform: "iOS",
            sourceBackend: "rig.stabilized"
        )
        let data = try encoder.encode(payload)
        try data.write(to: rigClipURL, options: .atomic)
        return rigClipURL
    }

    func read(for takeID: UUID) throws -> MotionClip? {
        let rigClipURL = rigClipURL(for: takeID)
        guard fileManager.fileExists(atPath: rigClipURL.path()) else {
            return nil
        }

        let decoder = JSONDecoder()
        let data = try Data(contentsOf: rigClipURL)
        return try decoder.decode(MotionPayload.self, from: data).makeMotionClip()
    }

    func removeRigClip(for takeID: UUID) throws {
        let rigClipURL = rigClipURL(for: takeID)
        guard fileManager.fileExists(atPath: rigClipURL.path()) else {
            return
        }

        try fileManager.removeItem(at: rigClipURL)
    }

    private func ensureBaseDirectoryExists() throws {
        guard !fileManager.fileExists(atPath: baseDirectoryURL.path()) else {
            return
        }

        try fileManager.createDirectory(at: baseDirectoryURL, withIntermediateDirectories: true)
    }
}
