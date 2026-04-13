//
//  MotionModels.swift
//  Odoro
//

import Foundation
import simd

enum StudioPresentation {
    case capture
    case stage
}

struct MotionFrame: Sendable {
    let time: TimeInterval
    let jointPositions: [SIMD3<Float>]
}

struct MotionClip: Sendable {
    let frames: [MotionFrame]

    var duration: TimeInterval {
        frames.last?.time ?? 0
    }

    var frameCount: Int {
        frames.count
    }

    var isEmpty: Bool {
        frames.isEmpty
    }

    func normalizedForStage() -> MotionClip {
        guard let firstFrame = frames.first, !frames.isEmpty else {
            return self
        }

        let firstAverage = firstFrame.jointPositions.reduce(SIMD3<Float>.zero, +) / Float(firstFrame.jointPositions.count)
        let floorHeight = frames
            .flatMap(\.jointPositions)
            .map(\.y)
            .min() ?? 0

        let origin = SIMD3<Float>(firstAverage.x, floorHeight, firstAverage.z)
        let normalizedFrames = frames.map { frame in
            MotionFrame(
                time: frame.time,
                jointPositions: frame.jointPositions.map { $0 - origin }
            )
        }

        return MotionClip(frames: normalizedFrames)
    }
}

struct MotionStudioState {
    var presentation: StudioPresentation = .capture
    var statusText = L10n.statusStandInFrame
    var isRecording = false
    var isPlaying = false
    var recordedFrameCount = 0
    var recordingDuration: TimeInterval = 0
    var clipDuration: TimeInterval = 0
    var hasClip = false
}
