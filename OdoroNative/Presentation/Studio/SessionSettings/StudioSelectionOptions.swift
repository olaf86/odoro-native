//
//  StudioSelectionOptions.swift
//  Odoro
//

import Foundation

struct TimeSignatureOption: Identifiable, Hashable {
    var numerator: Int
    var denominator: Int

    var id: String { "\(numerator)/\(denominator)" }
    var title: String { "\(numerator)/\(denominator)" }
}

struct AudioSourceOption: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let tempoSourceType: TempoSourceType
    let audioAssetReference: String?
    let preferredBPM: Double?

    func matches(_ context: MotionRecordingContext) -> Bool {
        guard context.tempoSourceType == tempoSourceType else {
            return false
        }

        return tempoSourceType == .metronome || context.audioAssetReference == audioAssetReference
    }

    var supportsPreview: Bool {
        tempoSourceType == .metronome
    }
}

enum StudioSelectionOptions {
    static let timeSignatures = [
        TimeSignatureOption(numerator: 3, denominator: 4),
        TimeSignatureOption(numerator: 4, denominator: 4),
    ]

    static let audioSources = [
        AudioSourceOption(
            id: "metronome",
            title: "Metronome",
            subtitle: "A clean click track for precise timing.",
            tempoSourceType: .metronome,
            audioAssetReference: nil,
            preferredBPM: nil
        ),
        AudioSourceOption(
            id: "house-loop",
            title: "House Loop",
            subtitle: "124 BPM reference loop for groove takes.",
            tempoSourceType: .audioAsset,
            audioAssetReference: "house-loop-demo",
            preferredBPM: 124
        ),
        AudioSourceOption(
            id: "hiphop-loop",
            title: "Hip-Hop Loop",
            subtitle: "96 BPM pocket for upper-body practice.",
            tempoSourceType: .audioAsset,
            audioAssetReference: "hiphop-loop-demo",
            preferredBPM: 96
        ),
        AudioSourceOption(
            id: "breaks-loop",
            title: "Breaks Loop",
            subtitle: "132 BPM for sharper accent checks.",
            tempoSourceType: .audioAsset,
            audioAssetReference: "breaks-loop-demo",
            preferredBPM: 132
        ),
    ]

    static func audioSource(matching context: MotionRecordingContext) -> AudioSourceOption {
        audioSources.first(where: { $0.matches(context) }) ?? audioSources[0]
    }

    static func timeSignature(for context: MotionRecordingContext) -> TimeSignatureOption {
        TimeSignatureOption(
            numerator: context.timeSignatureNumerator,
            denominator: context.timeSignatureDenominator
        )
    }

    static func sessionSummaryText(for context: MotionRecordingContext) -> String {
        let audioSource = audioSource(matching: context)
        let bpm = Int(context.bpm.rounded())
        let timeSignature = timeSignature(for: context)
        return "\(audioSource.title) • \(bpm) BPM • \(timeSignature.title) • \(context.targetBarCount) bars"
    }
}
