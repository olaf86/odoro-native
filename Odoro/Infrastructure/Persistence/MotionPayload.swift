//
//  MotionPayload.swift
//  Odoro
//

import Foundation
import simd

struct MotionPayloadVector3: Codable, Sendable {
    var x: Float
    var y: Float
    var z: Float

    init(x: Float, y: Float, z: Float) {
        self.x = x
        self.y = y
        self.z = z
    }

    init(_ vector: SIMD3<Float>) {
        self.init(x: vector.x, y: vector.y, z: vector.z)
    }

    var simdValue: SIMD3<Float> {
        SIMD3<Float>(x, y, z)
    }
}

struct MotionPayloadQuaternion: Codable, Sendable {
    var ix: Float
    var iy: Float
    var iz: Float
    var r: Float

    nonisolated init(_ rotation: MotionJointRotation) {
        self.ix = rotation.ix
        self.iy = rotation.iy
        self.iz = rotation.iz
        self.r = rotation.r
    }

    var motionValue: MotionJointRotation {
        MotionJointRotation(ix: ix, iy: iy, iz: iz, r: r)
    }
}

struct MotionPayloadFrame: Codable, Sendable {
    var timeSeconds: Double
    var timeBeats: Double
    var positions: [MotionPayloadVector3]
    var rotations: [MotionPayloadQuaternion?]?
    var confidences: [Float]?
    var jointStatuses: [OdoroJointStatus]?
}

struct MotionPayload: Codable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var skeletonId: String
    var jointNames: [OdoroJointName]
    var jointCount: Int
    var captureMode: CaptureMode
    var sourcePlatform: String
    var sourceBackend: String
    var frames: [MotionPayloadFrame]

    init(
        clip: MotionClip,
        captureMode: CaptureMode,
        recordingContext: MotionRecordingContext,
        sourcePlatform: String,
        sourceBackend: String
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.skeletonId = OdoroSkeletonDefinition.id
        self.jointNames = OdoroSkeletonDefinition.jointNames
        self.jointCount = OdoroSkeletonDefinition.jointCount
        self.captureMode = captureMode
        self.sourcePlatform = sourcePlatform
        self.sourceBackend = sourceBackend
        self.frames = clip.frames.map { frame in
            let canonicalFrame = OdoroCanonicalPoseMapper.map(frame: frame)
            return MotionPayloadFrame(
                timeSeconds: frame.time,
                timeBeats: frame.time * recordingContext.bpm / 60,
                positions: canonicalFrame.positions,
                rotations: canonicalFrame.rotations?.map { $0.map(MotionPayloadQuaternion.init) },
                confidences: nil,
                jointStatuses: canonicalFrame.statuses
            )
        }
    }

    func makeMotionClip() -> MotionClip {
        MotionClip(
            frames: frames.map { frame in
                let rotations = frame.rotations?.count == frame.positions.count
                    ? frame.rotations?.map { $0?.motionValue }
                    : nil
                return MotionFrame(
                    time: frame.timeSeconds,
                    jointPositions: frame.positions.map(\.simdValue),
                    jointRotations: rotations
                )
            }
        )
    }
}
