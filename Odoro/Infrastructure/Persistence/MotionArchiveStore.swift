//
//  MotionArchiveStore.swift
//  Odoro
//

import Foundation
import SwiftData

struct MotionTakeSaveResult: Sendable {
    var sessionID: UUID
    var takeID: UUID
    var localFilePath: String
}

@MainActor
final class MotionArchiveStore {
    private let modelContainer: ModelContainer
    private let payloadFileStore: MotionPayloadFileStore

    init(modelContainer: ModelContainer, payloadFileStore: MotionPayloadFileStore? = nil) {
        self.modelContainer = modelContainer
        self.payloadFileStore = payloadFileStore ?? MotionPayloadFileStore()
    }

    func saveTake(
        clip: MotionClip,
        captureMode: CaptureMode,
        recordingContext: MotionRecordingContext,
        existingSessionID: UUID? = nil,
        startBeatOffset: Double = 0
    ) throws -> MotionTakeSaveResult {
        let context = ModelContext(modelContainer)
        let session = try fetchOrCreateSession(
            withID: existingSessionID,
            recordingContext: recordingContext,
            context: context
        )
        let takeID = UUID()
        let payload = MotionPayload(
            clip: clip,
            captureMode: captureMode,
            recordingContext: recordingContext,
            sourcePlatform: "iOS",
            sourceBackend: sourceBackendName(for: captureMode)
        )
        let payloadURL = try payloadFileStore.write(payload, for: takeID)

        do {
            let take = MotionTakeRecord(
                id: takeID,
                takeIndex: nextTakeIndex(in: session),
                captureMode: captureMode,
                durationSeconds: clip.duration,
                frameCount: clip.frameCount,
                nominalFrameRate: clip.estimatedFrameRate,
                barLength: recordingContext.targetBarCount,
                beatLength: recordingContext.beatLength,
                startBeatOffset: startBeatOffset,
                localFilePath: payloadURL.path(),
                session: session
            )
            context.insert(take)
            try context.save()
        } catch {
            try? FileManager.default.removeItem(at: payloadURL)
            throw error
        }

        return MotionTakeSaveResult(
            sessionID: session.id,
            takeID: takeID,
            localFilePath: payloadURL.path()
        )
    }

    func loadClip(fromLocalFilePath localFilePath: String) throws -> MotionClip {
        let payloadURL = URL(fileURLWithPath: localFilePath)
        return try payloadFileStore.read(from: payloadURL).makeMotionClip()
    }

    private func fetchOrCreateSession(
        withID sessionID: UUID?,
        recordingContext: MotionRecordingContext,
        context: ModelContext
    ) throws -> RecordingSessionRecord {
        if let sessionID, let existingSession = try fetchSession(withID: sessionID, context: context) {
            return existingSession
        }

        let session = RecordingSessionRecord(
            id: sessionID ?? UUID(),
            recordingContext: recordingContext
        )
        context.insert(session)
        return session
    }

    private func fetchSession(withID sessionID: UUID, context: ModelContext) throws -> RecordingSessionRecord? {
        let descriptor = FetchDescriptor<RecordingSessionRecord>(
            predicate: #Predicate { session in
                session.id == sessionID
            }
        )
        return try context.fetch(descriptor).first
    }

    private func nextTakeIndex(in session: RecordingSessionRecord) -> Int {
        (session.takes.map(\.takeIndex).max() ?? 0) + 1
    }

    private func sourceBackendName(for captureMode: CaptureMode) -> String {
        switch captureMode {
        case .rearBody3D:
            "arkit.bodyTracking"
        case .frontUpperBody:
            "vision.frontBodyPose"
        case .mock:
            "mock.procedural"
        }
    }
}
