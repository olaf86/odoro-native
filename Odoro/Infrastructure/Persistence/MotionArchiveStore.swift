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
    var clipName: String?
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
    var tempoSourceType: TempoSourceType
    var audioAssetReference: String?
    var bpm: Double
    var timeSignatureNumerator: Int
    var timeSignatureDenominator: Int
    var countInBarCount: Int
}

@MainActor
final class MotionArchiveStore {
    enum ArchiveStoreError: LocalizedError {
        case missingTake(UUID)

        var errorDescription: String? {
            switch self {
            case let .missingTake(takeID):
                "The motion take \(takeID.uuidString) could not be found."
            }
        }
    }

    private let modelContainer: ModelContainer
    private let payloadFileStore: MotionPayloadFileStore
    private let sourceClipFileStore: MotionSourceClipFileStore
    private let hintsFileStore: MotionPlaybackHintsFileStore
    private let rigClipFileStore: MotionRigClipFileStore
    private let artifactsBuilder: MotionTakeArtifactsBuilder

    init(
        modelContainer: ModelContainer,
        payloadFileStore: MotionPayloadFileStore? = nil,
        sourceClipFileStore: MotionSourceClipFileStore? = nil,
        hintsFileStore: MotionPlaybackHintsFileStore? = nil,
        hintsBuilder: MotionPlaybackHintsBuilder = MotionPlaybackHintsBuilder(),
        rigClipFileStore: MotionRigClipFileStore? = nil,
        artifactsBuilder: MotionTakeArtifactsBuilder? = nil
    ) {
        self.modelContainer = modelContainer
        self.payloadFileStore = payloadFileStore ?? MotionPayloadFileStore()
        self.sourceClipFileStore = sourceClipFileStore ?? MotionSourceClipFileStore()
        self.hintsFileStore = hintsFileStore ?? MotionPlaybackHintsFileStore()
        self.rigClipFileStore = rigClipFileStore ?? MotionRigClipFileStore()
        self.artifactsBuilder = artifactsBuilder ?? MotionTakeArtifactsBuilder(hintsBuilder: hintsBuilder)
    }

    func saveTake(
        sourceClip: MotionClip,
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
        let artifacts = artifactsBuilder.buildArtifacts(
            from: sourceClip,
            captureMode: captureMode
        )

        let payload = MotionPayload(
            clip: artifacts.playbackClip,
            clipIsCanonical: true,
            captureMode: captureMode,
            recordingContext: recordingContext,
            sourcePlatform: "iOS",
            sourceBackend: sourceBackendName(for: captureMode)
        )
        let cachedPlaybackClip = payload.makeMotionClip()
        let payloadURL: URL
        let sourceBackend = sourceBackendName(for: captureMode)
        do {
            payloadURL = try payloadFileStore.write(payload, for: takeID)
            _ = try sourceClipFileStore.write(
                sourceClip,
                for: takeID,
                captureMode: captureMode,
                sourceBackend: sourceBackend
            )
            _ = try hintsFileStore.write(artifacts.hints, for: takeID)
            _ = try rigClipFileStore.write(
                artifacts.rigClip,
                for: takeID,
                captureMode: captureMode,
                recordingContext: recordingContext
            )
        } catch {
            try? payloadFileStore.removePayload(for: takeID)
            try? sourceClipFileStore.removeSourceClip(for: takeID)
            try? hintsFileStore.removeHints(for: takeID)
            try? rigClipFileStore.removeRigClip(for: takeID)
            throw error
        }

        do {
            let takeIndex = nextTakeIndex(in: session)
            let take = MotionTakeRecord(
                id: takeID,
                clipName: defaultClipName(for: takeIndex),
                takeIndex: takeIndex,
                captureMode: captureMode,
                durationSeconds: cachedPlaybackClip.duration,
                frameCount: cachedPlaybackClip.frameCount,
                nominalFrameRate: cachedPlaybackClip.estimatedFrameRate,
                barLength: recordingContext.targetBarCount,
                beatLength: recordingContext.beatLength,
                startBeatOffset: startBeatOffset,
                isAccepted: false,
                localFilePath: payloadURL.path(),
                session: session
            )
            context.insert(take)
            try context.save()
        } catch {
            try? payloadFileStore.removePayload(for: takeID)
            try? sourceClipFileStore.removeSourceClip(for: takeID)
            try? hintsFileStore.removeHints(for: takeID)
            try? rigClipFileStore.removeRigClip(for: takeID)
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

    func loadStoredTake(withID takeID: UUID) throws -> StoredMotionTake {
        guard let summary = try fetchTakeSummary(withID: takeID) else {
            throw ArchiveStoreError.missingTake(takeID)
        }

        if let sourceClip = try? sourceClipFileStore.read(for: takeID) {
            return artifactsBuilder.buildStoredTake(from: sourceClip, captureMode: summary.captureMode)
        }

        // Source clip file is absent for takes recorded before source-clip persistence was
        // introduced. Fall back to the cached playback clip stored in the payload file.
        // Use payloadURL(for:) rather than the stored localFilePath so the path is always
        // resolved relative to the current app container (localFilePath becomes stale after
        // app reinstall because the container UUID changes).
        let payloadURL = payloadFileStore.payloadURL(for: takeID)
        let payloadClip = try payloadFileStore.read(from: payloadURL).makeMotionClip()
        let rigClip = (try? rigClipFileStore.read(for: takeID)) ?? payloadClip.rigNormalizedForStage()
        let hints = (try? hintsFileStore.read(for: takeID))
            ?? artifactsBuilder.hintsBuilder.build(playbackClip: payloadClip, captureMode: summary.captureMode)
        return StoredMotionTake(
            clip: payloadClip,
            sourceClip: payloadClip,
            rigClip: rigClip,
            hints: hints
        )
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
        return try makeTakeSummaries(from: context.fetch(descriptor), fallbackSessionID: sessionID)
    }

    func fetchAllTakeSummaries() throws -> [MotionTakeSummary] {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<MotionTakeRecord>()
        return try makeTakeSummaries(from: context.fetch(descriptor), fallbackSessionID: nil)
    }

    private func fetchTakeSummary(withID takeID: UUID) throws -> MotionTakeSummary? {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<MotionTakeRecord>(
            predicate: #Predicate { take in
                take.id == takeID
            }
        )
        return try makeTakeSummaries(from: context.fetch(descriptor), fallbackSessionID: nil).first
    }

    func acceptTake(withID takeID: UUID, inSessionID sessionID: UUID) throws {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<MotionTakeRecord>(
            predicate: #Predicate { take in
                take.session?.id == sessionID
            }
        )
        let takes = try context.fetch(descriptor)
        guard takes.contains(where: { $0.id == takeID }) else {
            return
        }

        var didChange = false

        for take in takes {
            let shouldBeAccepted = take.id == takeID
            guard take.isAccepted != shouldBeAccepted else {
                continue
            }

            take.isAccepted = shouldBeAccepted
            didChange = true
        }

        if didChange {
            try context.save()
        }
    }

    func renameTake(withID takeID: UUID, clipName: String) throws {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<MotionTakeRecord>(
            predicate: #Predicate { take in
                take.id == takeID
            }
        )
        guard let take = try context.fetch(descriptor).first else {
            return
        }

        take.clipName = clipName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? defaultClipName(for: take.takeIndex)
            : clipName.trimmingCharacters(in: .whitespacesAndNewlines)
        try context.save()
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

    private func defaultClipName(for takeIndex: Int) -> String {
        "Clip \(takeIndex)"
    }

    private func makeTakeSummaries(
        from takes: [MotionTakeRecord],
        fallbackSessionID: UUID?
    ) -> [MotionTakeSummary] {
        takes
            .sorted { lhs, rhs in
                if lhs.createdAt == rhs.createdAt {
                    return lhs.takeIndex > rhs.takeIndex
                }

                return lhs.createdAt > rhs.createdAt
            }
            .compactMap { take in
                guard let session = take.session else {
                    guard let fallbackSessionID else {
                        return nil
                    }

                    return MotionTakeSummary(
                        id: take.id,
                        sessionID: fallbackSessionID,
                        createdAt: take.createdAt,
                        clipName: take.clipName ?? defaultClipName(for: take.takeIndex),
                        takeIndex: take.takeIndex,
                        captureMode: take.captureMode,
                        durationSeconds: take.durationSeconds,
                        frameCount: take.frameCount,
                        nominalFrameRate: take.nominalFrameRate,
                        barLength: take.barLength,
                        beatLength: take.beatLength,
                        startBeatOffset: take.startBeatOffset,
                        isAccepted: take.isAccepted,
                        localFilePath: take.localFilePath,
                        tempoSourceType: .metronome,
                        audioAssetReference: nil,
                        bpm: 120,
                        timeSignatureNumerator: 4,
                        timeSignatureDenominator: 4,
                        countInBarCount: 1
                    )
                }

                return MotionTakeSummary(
                    id: take.id,
                    sessionID: session.id,
                    createdAt: take.createdAt,
                    clipName: take.clipName ?? defaultClipName(for: take.takeIndex),
                    takeIndex: take.takeIndex,
                    captureMode: take.captureMode,
                    durationSeconds: take.durationSeconds,
                    frameCount: take.frameCount,
                    nominalFrameRate: take.nominalFrameRate,
                    barLength: take.barLength,
                    beatLength: take.beatLength,
                    startBeatOffset: take.startBeatOffset,
                    isAccepted: take.isAccepted,
                    localFilePath: take.localFilePath,
                    tempoSourceType: session.tempoSourceType,
                    audioAssetReference: session.audioAssetReference,
                    bpm: session.bpm,
                    timeSignatureNumerator: session.timeSignatureNumerator,
                    timeSignatureDenominator: session.timeSignatureDenominator,
                    countInBarCount: session.countInBarCount
                )
            }
    }

    private func sourceBackendName(for captureMode: CaptureMode) -> String {
        switch captureMode {
        case .rearBody3D:
            "arkit.bodyTracking"
        case .frontUpperBody:
            "vision.frontBodyPose"
        case .importedVideo:
            "vision.videoImport"
        case .mock:
            "mock.procedural"
        }
    }
}
