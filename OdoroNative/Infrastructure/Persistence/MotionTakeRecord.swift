//
//  MotionTakeRecord.swift
//  Odoro
//

import Foundation
import SwiftData

enum MotionTakeUploadStatus: String, Codable, Sendable {
    case localOnly
    case pendingUpload
    case uploaded
    case failed
}

@Model
final class MotionTakeRecord {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var clipName: String?
    var takeIndex: Int
    var captureModeRawValue: String
    var durationSeconds: Double
    var frameCount: Int
    var nominalFrameRate: Double
    var barLength: Int
    var beatLength: Double
    var startBeatOffset: Double
    var isAccepted: Bool
    var localFilePath: String
    var uploadStatusRawValue: String
    var remoteObjectKey: String?
    var schemaVersion: Int

    var session: RecordingSessionRecord?

    var captureMode: CaptureMode {
        get { CaptureMode(rawValue: captureModeRawValue) ?? .mock }
        set { captureModeRawValue = newValue.rawValue }
    }

    var uploadStatus: MotionTakeUploadStatus {
        get { MotionTakeUploadStatus(rawValue: uploadStatusRawValue) ?? .localOnly }
        set { uploadStatusRawValue = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        clipName: String? = nil,
        takeIndex: Int,
        captureMode: CaptureMode,
        durationSeconds: Double,
        frameCount: Int,
        nominalFrameRate: Double,
        barLength: Int,
        beatLength: Double,
        startBeatOffset: Double,
        isAccepted: Bool = false,
        localFilePath: String,
        uploadStatus: MotionTakeUploadStatus = .localOnly,
        remoteObjectKey: String? = nil,
        schemaVersion: Int = MotionPayload.currentSchemaVersion,
        session: RecordingSessionRecord?
    ) {
        self.id = id
        self.createdAt = createdAt
        self.clipName = clipName
        self.takeIndex = takeIndex
        self.captureModeRawValue = captureMode.rawValue
        self.durationSeconds = durationSeconds
        self.frameCount = frameCount
        self.nominalFrameRate = nominalFrameRate
        self.barLength = barLength
        self.beatLength = beatLength
        self.startBeatOffset = startBeatOffset
        self.isAccepted = isAccepted
        self.localFilePath = localFilePath
        self.uploadStatusRawValue = uploadStatus.rawValue
        self.remoteObjectKey = remoteObjectKey
        self.schemaVersion = schemaVersion
        self.session = session
    }
}
