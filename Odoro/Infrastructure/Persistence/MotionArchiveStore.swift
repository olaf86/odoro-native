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

struct RecordingSessionSummary: Identifiable, Sendable {
    var id: UUID
    var createdAt: Date
    var bpm: Double
    var timeSignatureNumerator: Int
    var timeSignatureDenominator: Int
    var targetBarCount: Int
    var countInBarCount: Int
    var takeCount: Int

    var recordingContext: MotionRecordingContext {
        MotionRecordingContext(
            tempoSourceType: .metronome,
            audioAssetReference: nil,
            bpm: bpm,
            timeSignatureNumerator: timeSignatureNumerator,
            timeSignatureDenominator: timeSignatureDenominator,
            targetBarCount: targetBarCount,
            countInBarCount: countInBarCount,
            notes: nil
        )
    }
}

struct MotionTakeSummary: Identifiable, Sendable {
    var id: UUID
    var sessionID: UUID
    var createdAt: Date
    var takeIndex: Int
    var captureMode: CaptureMode
    var durationSeconds: Double
    var frameCount: Int
    var nominalFrameRate: Double
    var barLength: Int
    var beatLength: Double
    var startBeatOffset: Double
    var isAccepted: Bool
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

    func fetchSessionSummary(withID sessionID: UUID) throws -> RecordingSessionSummary? {
        let context = ModelContext(modelContainer)
        guard let session = try fetchSession(withID: sessionID, context: context) else {
            return nil
        }

        return RecordingSessionSummary(
            id: session.id,
            createdAt: session.createdAt,
            bpm: session.bpm,
            timeSignatureNumerator: session.timeSignatureNumerator,
            timeSignatureDenominator: session.timeSignatureDenominator,
            targetBarCount: session.targetBarCount,
            countInBarCount: session.countInBarCount,
            takeCount: session.takes.count
        )
    }

    func fetchTakeSummaries(inSessionID sessionID: UUID) throws -> [MotionTakeSummary] {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<MotionTakeRecord>(
            predicate: #Predicate { take in
                take.session?.id == sessionID
            }
        )
        return try context.fetch(descriptor)
            .sorted { lhs, rhs in
                if lhs.takeIndex == rhs.takeIndex {
                    return lhs.createdAt > rhs.createdAt
                }

                return lhs.takeIndex > rhs.takeIndex
            }
            .map { take in
                MotionTakeSummary(
                    id: take.id,
                    sessionID: take.session?.id ?? sessionID,
                    createdAt: take.createdAt,
                    takeIndex: take.takeIndex,
                    captureMode: take.captureMode,
                    durationSeconds: take.durationSeconds,
                    frameCount: take.frameCount,
                    nominalFrameRate: take.nominalFrameRate,
                    barLength: take.barLength,
                    beatLength: take.beatLength,
                    startBeatOffset: take.startBeatOffset,
                    isAccepted: take.isAccepted,
                    localFilePath: take.localFilePath
                )
            }
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
