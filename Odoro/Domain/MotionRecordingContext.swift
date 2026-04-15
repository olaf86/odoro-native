//
//  MotionRecordingContext.swift
//  Odoro
//

import Foundation

enum TempoSourceType: String, Codable, Sendable {
    case metronome
    case audioAsset
}

struct MotionRecordingContext: Codable, Sendable {
    var tempoSourceType: TempoSourceType
    var audioAssetReference: String?
    var bpm: Double
    var timeSignatureNumerator: Int
    var timeSignatureDenominator: Int
    var targetBarCount: Int
    var countInBarCount: Int
    var notes: String?

    var beatLength: Double {
        Double(targetBarCount * timeSignatureNumerator)
    }

    static let defaultMetronomeLoop = MotionRecordingContext(
        tempoSourceType: .metronome,
        audioAssetReference: nil,
        bpm: 120,
        timeSignatureNumerator: 4,
        timeSignatureDenominator: 4,
        targetBarCount: 2,
        countInBarCount: 1,
        notes: nil
    )
}
