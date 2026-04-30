//
//  StagePreparedPlayback.swift
//  Odoro
//

import Foundation
import simd

struct ClipVariant: Sendable {
    enum Purpose: Sendable, Equatable {
        case display
        case avatarRig
    }

    enum ProcessingStage: Sendable, Equatable {
        case raw
        case canonical
        case stabilized
    }

    enum SkeletonDefinition: Sendable, Equatable {
        case source
        case odoroCanonical
    }

    enum Integrity: Sendable, Equatable {
        case rigSafe
        case displaySafe
    }

    let purpose: Purpose
    let processingStage: ProcessingStage
    let clip: MotionClip?
    let appendagePoses: MotionClipAppendagePoses?
    let cameraPreset: StagePlaybackCameraPreset?
    let skeletonDefinition: SkeletonDefinition
    let integrity: Integrity
    let stabilizationProfile: MotionClipStageStabilizer.Profile?

    nonisolated static func empty(
        purpose: Purpose,
        processingStage: ProcessingStage,
        skeletonDefinition: SkeletonDefinition,
        integrity: Integrity
    ) -> Self {
        Self(
            purpose: purpose,
            processingStage: processingStage,
            clip: nil,
            appendagePoses: nil,
            cameraPreset: nil,
            skeletonDefinition: skeletonDefinition,
            integrity: integrity,
            stabilizationProfile: nil
        )
    }
}

typealias PreparedStagePlaybackClip = ClipVariant

struct StagePreparedPlayback: Sendable {
    let variants: [ClipVariant]

    nonisolated init(variants: [ClipVariant]) {
        self.variants = variants
    }

    nonisolated var raw: ClipVariant {
        variant(
            purpose: .display,
            processingStage: .raw
        ) ?? .empty(
            purpose: .display,
            processingStage: .raw,
            skeletonDefinition: .source,
            integrity: .displaySafe
        )
    }

    nonisolated var canonical: ClipVariant {
        variant(
            purpose: .display,
            processingStage: .canonical
        ) ?? .empty(
            purpose: .display,
            processingStage: .canonical,
            skeletonDefinition: .odoroCanonical,
            integrity: .displaySafe
        )
    }

    nonisolated var stabilized: ClipVariant {
        variant(
            purpose: .display,
            processingStage: .stabilized
        ) ?? .empty(
            purpose: .display,
            processingStage: .stabilized,
            skeletonDefinition: .odoroCanonical,
            integrity: .displaySafe
        )
    }

    nonisolated var avatarRigVariant: ClipVariant? {
        preferredVariant(
            for: [
                (.avatarRig, .stabilized),
                (.display, .raw),
            ],
            integrity: .rigSafe
        )
    }

    nonisolated private func preferredVariant(
        for preferredSelections: [(ClipVariant.Purpose, ClipVariant.ProcessingStage)],
        integrity: ClipVariant.Integrity
    ) -> ClipVariant? {
        for (purpose, processingStage) in preferredSelections {
            guard let variant = variant(purpose: purpose, processingStage: processingStage) else {
                continue
            }

            if variant.integrity == integrity,
               variant.clip != nil {
                return variant
            }
        }

        return nil
    }

    nonisolated func variant(
        purpose: ClipVariant.Purpose,
        processingStage: ClipVariant.ProcessingStage
    ) -> ClipVariant? {
        variants.first { variant in
            variant.purpose == purpose && variant.processingStage == processingStage
        }
    }
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
        let rigStabilizedClip = sourceClip?.rigNormalizedForStage()
        let rawIntegrity: ClipVariant.Integrity = sourceClip == nil ? .displaySafe : .rigSafe

        var variants: [ClipVariant] = [
            buildVariant(
                purpose: .display,
                processingStage: .raw,
                clip: rawClip,
                appendagePoses: nil,
                storedPreset: playbackArtifacts?.stagePlayback?.raw.cameraPreset,
                skeletonDefinition: rawIntegrity == .rigSafe ? .source : inferredSkeletonDefinition(for: rawClip),
                integrity: rawIntegrity,
                stabilizationProfile: nil
            ),
            buildVariant(
                purpose: .display,
                processingStage: .canonical,
                clip: canonicalClip,
                appendagePoses: resolvedAppendagePoses(
                    for: canonicalClip,
                    captureMode: captureMode,
                    sourceClip: sourceClip,
                    storedPoses: playbackArtifacts?.stagePlayback?.canonical.appendagePoses
                ),
                storedPreset: playbackArtifacts?.stagePlayback?.canonical.cameraPreset,
                skeletonDefinition: .odoroCanonical,
                integrity: .displaySafe,
                stabilizationProfile: nil
            ),
            buildVariant(
                purpose: .display,
                processingStage: .stabilized,
                clip: stabilizedClip,
                appendagePoses: resolvedAppendagePoses(
                    for: stabilizedClip,
                    captureMode: captureMode,
                    sourceClip: sourceClip,
                    storedPoses: playbackArtifacts?.stagePlayback?.stabilized.appendagePoses
                ),
                storedPreset: playbackArtifacts?.stagePlayback?.stabilized.cameraPreset,
                skeletonDefinition: inferredSkeletonDefinition(for: stabilizedClip),
                integrity: .displaySafe,
                stabilizationProfile: .displaySafe
            ),
        ]

        if let rigStabilizedClip {
            variants.append(
                buildVariant(
                    purpose: .avatarRig,
                    processingStage: .stabilized,
                    clip: rigStabilizedClip,
                    appendagePoses: nil,
                    storedPreset: nil,
                    skeletonDefinition: .source,
                    integrity: .rigSafe,
                    stabilizationProfile: .rigSafe
                )
            )
        }

        return StagePreparedPlayback(variants: variants)
    }

    nonisolated private func buildVariant(
        purpose: ClipVariant.Purpose,
        processingStage: ClipVariant.ProcessingStage,
        clip: MotionClip?,
        appendagePoses: MotionClipAppendagePoses?,
        storedPreset: StagePlaybackCameraPreset?,
        skeletonDefinition: ClipVariant.SkeletonDefinition,
        integrity: ClipVariant.Integrity,
        stabilizationProfile: MotionClipStageStabilizer.Profile?
    ) -> ClipVariant {
        ClipVariant(
            purpose: purpose,
            processingStage: processingStage,
            clip: clip,
            appendagePoses: appendagePoses,
            cameraPreset: resolvedCameraPreset(
                for: clip,
                storedPreset: storedPreset
            ),
            skeletonDefinition: skeletonDefinition,
            integrity: integrity,
            stabilizationProfile: stabilizationProfile
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

    nonisolated private func inferredSkeletonDefinition(for clip: MotionClip?) -> ClipVariant.SkeletonDefinition {
        guard let jointCount = clip?.frames.first?.jointPositions.count else {
            return .source
        }

        if jointCount == OdoroSkeletonDefinition.jointCount {
            return .odoroCanonical
        }

        return .source
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
