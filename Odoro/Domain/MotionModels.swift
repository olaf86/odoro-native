//
//  MotionModels.swift
//  Odoro
//

import Foundation
import simd

enum StudioPresentation: Equatable {
    case capture
    case stage
}

enum StudioScreen: String, Equatable {
    case capture
    case musicSelection
    case sessionSettings
    case clipsLibrary
    case stage
    case modelSelection
    case archive
}

enum StudioScreenTransition: Equatable {
    case fromLeading
    case fromTrailing
    case fromTop
    case fromBottom
}

struct MotionJointRotation: Codable, Sendable, Equatable, Hashable {
    let ix: Float
    let iy: Float
    let iz: Float
    let r: Float

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.ix == rhs.ix && lhs.iy == rhs.iy && lhs.iz == rhs.iz && lhs.r == rhs.r
    }

    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(ix)
        hasher.combine(iy)
        hasher.combine(iz)
        hasher.combine(r)
    }

    nonisolated init(ix: Float, iy: Float, iz: Float, r: Float) {
        self.ix = ix
        self.iy = iy
        self.iz = iz
        self.r = r
    }

    nonisolated init(_ quaternion: simd_quatf) {
        let vector = quaternion.vector
        self.init(ix: vector.x, iy: vector.y, iz: vector.z, r: vector.w)
    }

    nonisolated var simdValue: simd_quatf {
        simd_quatf(vector: SIMD4<Float>(ix, iy, iz, r))
    }
}

struct MotionFrame: Sendable {
    let time: TimeInterval
    let jointPositions: [SIMD3<Float>]
    let jointRotations: [MotionJointRotation?]?

    nonisolated init(
        time: TimeInterval,
        jointPositions: [SIMD3<Float>],
        jointRotations: [MotionJointRotation?]? = nil
    ) {
        self.time = time
        self.jointPositions = jointPositions
        self.jointRotations = jointRotations
    }
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

    var estimatedFrameRate: Double {
        guard frames.count > 1, duration > 0 else {
            return 0
        }

        return Double(frames.count - 1) / duration
    }

    nonisolated func normalizedForStage() -> MotionClip {
        MotionClipStageNormalizer().normalized(clip: self)
    }

    nonisolated func rigNormalizedForStage() -> MotionClip {
        MotionClipStageNormalizer(stabilizationProfile: .rigSafe).normalized(clip: self)
    }

    nonisolated func rebasedForStage() -> MotionClip {
        MotionClipStageRebaser().rebased(clip: self)
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
