//
//  RecordingSessionRecord.swift
//  Odoro
//

import Foundation
import SwiftData

@Model
final class RecordingSessionRecord {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var tempoSourceTypeRawValue: String
    var audioAssetReference: String?
    var referenceBPM: Double
    var timeSignatureNumerator: Int
    var timeSignatureDenominator: Int
    var targetBarCount: Int
    var countInBarCount: Int
    var notes: String?

    @Relationship(deleteRule: .cascade, inverse: \MotionTakeRecord.session)
    var takes: [MotionTakeRecord] = []

    var tempoSourceType: TempoSourceType {
        get { TempoSourceType(rawValue: tempoSourceTypeRawValue) ?? .metronome }
        set { tempoSourceTypeRawValue = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        recordingContext: MotionRecordingContext
    ) {
        self.id = id
        self.createdAt = createdAt
        self.tempoSourceTypeRawValue = recordingContext.tempoSourceType.rawValue
        self.audioAssetReference = recordingContext.audioAssetReference
        self.referenceBPM = recordingContext.referenceBPM
        self.timeSignatureNumerator = recordingContext.timeSignatureNumerator
        self.timeSignatureDenominator = recordingContext.timeSignatureDenominator
        self.targetBarCount = recordingContext.targetBarCount
        self.countInBarCount = recordingContext.countInBarCount
        self.notes = recordingContext.notes
    }
}
