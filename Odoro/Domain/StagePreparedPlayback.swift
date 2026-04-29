//
//  StagePreparedPlayback.swift
//  Odoro
//

import Foundation
import simd

struct PreparedStagePlaybackClip: Sendable {
    let clip: MotionClip?
    let appendagePoses: MotionClipAppendagePoses?
    let cameraPreset: StagePlaybackCameraPreset?
}

struct StagePreparedPlayback: Sendable {
    let raw: PreparedStagePlaybackClip
    let canonical: PreparedStagePlaybackClip
    let stabilized: PreparedStagePlaybackClip
}

struct StagePreparedPlaybackBuilder: Sendable {
    let appendagePoseEstimator: RearBody3DAppendagePoseEstimator
    let cameraEstimator: StagePlaybackCameraEstimator

    nonisolated init(
        appendagePoseEstimator: RearBody3DAppendagePoseEstimator = RearBody3DAppendagePoseEstimator(),
        cameraEstimator: StagePlaybackCameraEstimator = StagePlaybackCameraEstimator()
    ) {
        self.appendagePoseEstimator = appendagePoseEstimator
        self.cameraEstimator = cameraEstimator
    }

    nonisolated func prepare(
        sourceClip: MotionClip?,
        playbackClip: MotionClip?,
        captureMode: CaptureMode,
        playbackArtifacts: MotionPlaybackArtifacts? = nil
    ) -> StagePreparedPlayback {
        let rawClip = (sourceClip ?? playbackClip)?.rebasedForStage()
        let canonicalClip = canonicalPlaybackClip(sourceClip: sourceClip, playbackClip: playbackClip)
        let stabilizedClip = playbackClip

        return StagePreparedPlayback(
            raw: PreparedStagePlaybackClip(
                clip: rawClip,
                appendagePoses: nil,
                cameraPreset: resolvedCameraPreset(
                    for: rawClip,
                    storedPreset: playbackArtifacts?.stagePlayback?.raw.cameraPreset
                )
            ),
            canonical: PreparedStagePlaybackClip(
                clip: canonicalClip,
                appendagePoses: resolvedAppendagePoses(
                    for: canonicalClip,
                    captureMode: captureMode,
                    sourceClip: sourceClip,
                    storedPoses: playbackArtifacts?.stagePlayback?.canonical.appendagePoses
                ),
                cameraPreset: resolvedCameraPreset(
                    for: canonicalClip,
                    storedPreset: playbackArtifacts?.stagePlayback?.canonical.cameraPreset
                )
            ),
            stabilized: PreparedStagePlaybackClip(
                clip: stabilizedClip,
                appendagePoses: resolvedAppendagePoses(
                    for: stabilizedClip,
                    captureMode: captureMode,
                    sourceClip: sourceClip,
                    storedPoses: playbackArtifacts?.stagePlayback?.stabilized.appendagePoses
                ),
                cameraPreset: resolvedCameraPreset(
                    for: stabilizedClip,
                    storedPreset: playbackArtifacts?.stagePlayback?.stabilized.cameraPreset
                )
            )
        )
    }

    nonisolated private func canonicalPlaybackClip(
        sourceClip: MotionClip?,
        playbackClip: MotionClip?
    ) -> MotionClip? {
        if let sourceClip {
            return OdoroCanonicalPoseMapper
                .canonicalizedClip(from: sourceClip)
                .rebasedForStage()
        }

        guard let playbackClip else {
            return nil
        }

        if playbackClip.frames.first?.jointPositions.count == OdoroSkeletonDefinition.jointCount {
            return playbackClip.rebasedForStage()
        }

        return OdoroCanonicalPoseMapper
            .canonicalizedClip(from: playbackClip)
            .rebasedForStage()
    }

    nonisolated private func resolvedAppendagePoses(
        for clip: MotionClip?,
        captureMode: CaptureMode,
        sourceClip: MotionClip?,
        storedPoses: MotionClipAppendagePoses?
    ) -> MotionClipAppendagePoses? {
        guard
            captureMode == .rearBody3D,
            let clip
        else {
            return nil
        }

        if sourceClip == nil,
           let storedPoses,
           storedPoses.frames.count == clip.frames.count {
            return storedPoses
        }

        guard clip.frames.first?.jointPositions.count == OdoroSkeletonDefinition.jointCount else {
            return nil
        }

        return appendagePoseEstimator.estimatePoses(for: clip)
    }

    nonisolated private func resolvedCameraPreset(
        for clip: MotionClip?,
        storedPreset: StagePlaybackCameraPreset?
    ) -> StagePlaybackCameraPreset? {
        if let storedPreset {
            return storedPreset
        }

        guard let clip else {
            return nil
        }

        return cameraEstimator.estimate(for: clip)
    }
}

struct StagePlaybackCameraEstimator: Sendable {
    struct Tuning: Sendable {
        let minimumFrameCount = 1
        let baseCameraDistance: Float = 3.4
        let maximumAdditionalDistance: Float = 0.8
        let cameraDistanceScale: Float = 0.45
        let cameraHeightOffset: Float = 0.4
        let minimumDirectionLength: Float = 0.0001

        nonisolated init() {}
    }

    let tuning: Tuning

    nonisolated init(tuning: Tuning = .init()) {
        self.tuning = tuning
    }

    nonisolated func estimate(for clip: MotionClip) -> StagePlaybackCameraPreset? {
        guard clip.frames.count >= tuning.minimumFrameCount else {
            return nil
        }

        let canonicalFrames = clip.frames.filter {
            $0.jointPositions.count == OdoroSkeletonDefinition.jointCount
        }
        guard !canonicalFrames.isEmpty else {
            return nil
        }

        let roots = canonicalFrames.compactMap(representativeRoot(in:))
        guard !roots.isEmpty else {
            return nil
        }

        let lookAt = SIMD3<Float>(
            median(roots.map(\.x)),
            median(roots.map(\.y)),
            median(roots.map(\.z))
        )

        let forward = representativeForward(in: canonicalFrames) ?? SIMD3<Float>(0, 0, 1)
        let horizontalRadius = roots
            .map { root in
                simd_length(SIMD2<Float>(root.x - lookAt.x, root.z - lookAt.z))
            }
            .max() ?? 0
        let cameraDistance = tuning.baseCameraDistance
            + min(horizontalRadius * tuning.cameraDistanceScale, tuning.maximumAdditionalDistance)
        let position = lookAt
            + forward * cameraDistance
            + SIMD3<Float>(0, tuning.cameraHeightOffset, 0)

        return StagePlaybackCameraPreset(lookAt: lookAt, position: position)
    }
}

private extension StagePlaybackCameraEstimator {
    nonisolated func representativeRoot(in frame: MotionFrame) -> SIMD3<Float>? {
        canonicalPosition(for: .root, in: frame)
    }

    nonisolated func representativeForward(in frames: [MotionFrame]) -> SIMD3<Float>? {
        let accumulated = frames.reduce(SIMD3<Float>.zero) { partial, frame in
            partial + (frameForward(in: frame) ?? .zero)
        }

        return normalizedOrNil(accumulated)
    }

    nonisolated func frameForward(in frame: MotionFrame) -> SIMD3<Float>? {
        guard let bodyRight = bodyRight(in: frame) else {
            return nil
        }

        let up = SIMD3<Float>(0, 1, 0)
        guard var forward = normalizedOrNil(simd_cross(bodyRight, up)) else {
            return nil
        }

        if let noseForward = noseForward(in: frame),
           simd_dot(forward, noseForward) < 0 {
            forward *= -1
        }

        return forward
    }

    nonisolated func bodyRight(in frame: MotionFrame) -> SIMD3<Float>? {
        let candidates = [
            jointDirection(from: .leftShoulder, to: .rightShoulder, in: frame),
            jointDirection(from: .leftHip, to: .rightHip, in: frame),
        ].compactMap { $0 }

        guard !candidates.isEmpty else {
            return nil
        }

        return normalizedOrNil(candidates.reduce(.zero, +))
    }

    nonisolated func noseForward(in frame: MotionFrame) -> SIMD3<Float>? {
        guard
            let root = canonicalPosition(for: .root, in: frame),
            let nose = canonicalPosition(for: .nose, in: frame) ?? canonicalPosition(for: .head, in: frame)
        else {
            return nil
        }

        return normalizedOrNil(SIMD3<Float>(nose.x - root.x, 0, nose.z - root.z))
    }

    nonisolated func jointDirection(
        from startJoint: OdoroJointName,
        to endJoint: OdoroJointName,
        in frame: MotionFrame
    ) -> SIMD3<Float>? {
        guard
            let start = canonicalPosition(for: startJoint, in: frame),
            let end = canonicalPosition(for: endJoint, in: frame)
        else {
            return nil
        }

        return normalizedOrNil(end - start)
    }

    nonisolated func canonicalPosition(for joint: OdoroJointName, in frame: MotionFrame) -> SIMD3<Float>? {
        let index = OdoroSkeletonDefinition.index(of: joint)
        guard frame.jointPositions.indices.contains(index) else {
            return nil
        }

        let position = frame.jointPositions[index]
        guard position.x.isFinite, position.y.isFinite, position.z.isFinite else {
            return nil
        }

        return position
    }

    nonisolated func normalizedOrNil(_ vector: SIMD3<Float>) -> SIMD3<Float>? {
        let length = simd_length(vector)
        guard length > tuning.minimumDirectionLength else {
            return nil
        }

        return vector / length
    }

    nonisolated func median(_ values: [Float]) -> Float {
        let sorted = values.sorted()
        guard !sorted.isEmpty else {
            return 0
        }

        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) * 0.5
        }

        return sorted[middle]
    }
}
