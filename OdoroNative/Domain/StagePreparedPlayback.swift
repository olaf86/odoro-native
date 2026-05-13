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

        nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
            switch (lhs, rhs) {
            case (.display, .display), (.avatarRig, .avatarRig):
                true
            default:
                false
            }
        }
    }

    enum ProcessingStage: Sendable, Equatable {
        case raw
        case canonical
        case stabilized

        nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
            switch (lhs, rhs) {
            case (.raw, .raw), (.canonical, .canonical), (.stabilized, .stabilized):
                true
            default:
                false
            }
        }
    }

    enum SkeletonDefinition: Sendable, Equatable {
        case source
        case odoroCanonical

        nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
            switch (lhs, rhs) {
            case (.source, .source), (.odoroCanonical, .odoroCanonical):
                true
            default:
                false
            }
        }
    }

    enum Integrity: Sendable, Equatable {
        case rigSafe
        case displaySafe

        nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
            switch (lhs, rhs) {
            case (.rigSafe, .rigSafe), (.displaySafe, .displaySafe):
                true
            default:
                false
            }
        }
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

private struct ClipVariantKey: Sendable {
    let purpose: ClipVariant.Purpose
    let processingStage: ClipVariant.ProcessingStage

    nonisolated static func display(_ processingStage: ClipVariant.ProcessingStage) -> Self {
        Self(purpose: .display, processingStage: processingStage)
    }

    nonisolated static func avatarRig(_ processingStage: ClipVariant.ProcessingStage) -> Self {
        Self(purpose: .avatarRig, processingStage: processingStage)
    }

    nonisolated func matches(_ variant: ClipVariant) -> Bool {
        variant.purpose == purpose && variant.processingStage == processingStage
    }

    nonisolated func resolve(in variants: [ClipVariant]) -> ClipVariant? {
        variants.first(where: matches(_:))
    }
}

private struct ClipVariantDefinition: Sendable {
    let key: ClipVariantKey
    let fallbackSkeletonDefinition: ClipVariant.SkeletonDefinition
    let fallbackIntegrity: ClipVariant.Integrity

    nonisolated func resolve(in variants: [ClipVariant]) -> ClipVariant {
        key.resolve(in: variants) ?? emptyVariant()
    }

    nonisolated func emptyVariant() -> ClipVariant {
        .empty(
            purpose: key.purpose,
            processingStage: key.processingStage,
            skeletonDefinition: fallbackSkeletonDefinition,
            integrity: fallbackIntegrity
        )
    }
}

private enum StagePreparedPlaybackVariantCatalog {
    nonisolated static let displayRaw = ClipVariantDefinition(
        key: .display(.raw),
        fallbackSkeletonDefinition: .source,
        fallbackIntegrity: .displaySafe
    )

    nonisolated static let displayCanonical = ClipVariantDefinition(
        key: .display(.canonical),
        fallbackSkeletonDefinition: .odoroCanonical,
        fallbackIntegrity: .displaySafe
    )

    nonisolated static let displayStabilized = ClipVariantDefinition(
        key: .display(.stabilized),
        fallbackSkeletonDefinition: .odoroCanonical,
        fallbackIntegrity: .displaySafe
    )

    nonisolated static let avatarRigStabilized = ClipVariantDefinition(
        key: .avatarRig(.stabilized),
        fallbackSkeletonDefinition: .source,
        fallbackIntegrity: .rigSafe
    )

    nonisolated static let displayDefinitions = [
        displayRaw,
        displayCanonical,
        displayStabilized,
    ]

    nonisolated static let avatarRigPreferredDefinitions = [
        avatarRigStabilized,
        displayRaw,
    ]
}

struct StagePreparedPlayback: Sendable {
    private struct PreferredVariantPolicy: Sendable {
        let preferredDefinitions: [ClipVariantDefinition]
        let requiredIntegrity: ClipVariant.Integrity

        nonisolated func resolve(in variants: [ClipVariant]) -> ClipVariant? {
            for definition in preferredDefinitions {
                let variant = definition.resolve(in: variants)

                if variant.integrity == requiredIntegrity,
                   variant.clip != nil {
                    return variant
                }
            }

            return nil
        }
    }

    let variants: [ClipVariant]

    nonisolated init(variants: [ClipVariant]) {
        self.variants = variants
    }

    nonisolated var raw: ClipVariant {
        StagePreparedPlaybackVariantCatalog.displayRaw.resolve(in: variants)
    }

    nonisolated var canonical: ClipVariant {
        StagePreparedPlaybackVariantCatalog.displayCanonical.resolve(in: variants)
    }

    nonisolated var stabilized: ClipVariant {
        StagePreparedPlaybackVariantCatalog.displayStabilized.resolve(in: variants)
    }

    nonisolated var avatarRigVariant: ClipVariant? {
        Self.avatarRigSelectionPolicy.resolve(in: variants)
    }

    nonisolated private static let avatarRigSelectionPolicy = PreferredVariantPolicy(
        preferredDefinitions: StagePreparedPlaybackVariantCatalog.avatarRigPreferredDefinitions,
        requiredIntegrity: .rigSafe
    )

    nonisolated func variant(
        purpose: ClipVariant.Purpose,
        processingStage: ClipVariant.ProcessingStage
    ) -> ClipVariant? {
        ClipVariantKey(
            purpose: purpose,
            processingStage: processingStage
        ).resolve(in: variants)
    }
}

struct StagePreparedPlaybackBuilder: Sendable {
    private struct VariantBuildContext {
        let sourceClip: MotionClip?
        let playbackClip: MotionClip?
        let captureMode: CaptureMode
        let hints: MotionPlaybackHints?
    }

    private enum VariantClipSeed {
        case source
        case playback
        case sourceOrPlayback

        nonisolated
        func resolve(in context: VariantBuildContext) -> MotionClip? {
            return switch self {
            case .source:
                context.sourceClip
            case .playback:
                context.playbackClip
            case .sourceOrPlayback:
                context.sourceClip ?? context.playbackClip
            }
        }
    }

    private enum VariantClipPass {
        case canonicalizeForPlayback
        case rebaseForStage
        case rigNormalizeForStage

        nonisolated
        func apply(to clip: MotionClip?) -> MotionClip? {
            guard let clip else {
                return nil
            }

            return switch self {
            case .canonicalizeForPlayback:
                clip.frames.first?.jointPositions.count == OdoroSkeletonDefinition.jointCount
                    ? clip
                    : OdoroCanonicalPoseMapper.canonicalizedClip(from: clip)
            case .rebaseForStage:
                clip.rebasedForStage()
            case .rigNormalizeForStage:
                clip.rigNormalizedForStage()
            }
        }
    }

    private struct VariantClipPlan {
        let seed: VariantClipSeed
        let passes: [VariantClipPass]

        nonisolated static func source(_ passes: [VariantClipPass]) -> Self {
            Self(seed: .source, passes: passes)
        }

        nonisolated static func playback() -> Self {
            Self(seed: .playback, passes: [])
        }

        nonisolated static func playback(_ passes: [VariantClipPass]) -> Self {
            Self(seed: .playback, passes: passes)
        }

        nonisolated static func sourceOrPlayback(_ passes: [VariantClipPass]) -> Self {
            Self(seed: .sourceOrPlayback, passes: passes)
        }

        nonisolated
        func resolve(in context: VariantBuildContext) -> MotionClip? {
            passes.reduce(seed.resolve(in: context)) { clip, pass in
                pass.apply(to: clip)
            }
        }
    }

    private enum VariantArtifactSlot {
        case raw
        case canonical
        case stabilized

        nonisolated
        func storedArtifacts(in context: VariantBuildContext) -> StagePlaybackClipHints? {
            guard let stage = context.hints?.stage else {
                return nil
            }

            return switch self {
            case .raw:
                stage.raw
            case .canonical:
                stage.canonical
            case .stabilized:
                stage.stabilized
            }
        }
    }

    private enum SkeletonDefinitionPolicy {
        case source
        case odoroCanonical
        case deriveFromClip
        case rawDisplayFallback

        nonisolated
        func resolve(
            clip: MotionClip?,
            context: VariantBuildContext,
            inferredSkeletonDefinition: (MotionClip?) -> ClipVariant.SkeletonDefinition
        ) -> ClipVariant.SkeletonDefinition {
            switch self {
            case .source:
                .source
            case .odoroCanonical:
                .odoroCanonical
            case .deriveFromClip:
                inferredSkeletonDefinition(clip)
            case .rawDisplayFallback:
                context.sourceClip == nil ? inferredSkeletonDefinition(clip) : .source
            }
        }
    }

    private enum IntegrityPolicy {
        case fixed(ClipVariant.Integrity)
        case rawDisplayFallback

        nonisolated
        func resolve(in context: VariantBuildContext) -> ClipVariant.Integrity {
            switch self {
            case .fixed(let integrity):
                integrity
            case .rawDisplayFallback:
                context.sourceClip == nil ? .displaySafe : .rigSafe
            }
        }
    }

    private enum AppendagePoseStrategy {
        case none
        case rearBodyEstimateOrStoredArtifact

        nonisolated
        func resolve(
            clip: MotionClip?,
            storedPoses: MotionClipAppendagePoses?,
            context: VariantBuildContext,
            appendagePoseEstimator: RearBody3DAppendagePoseEstimator
        ) -> MotionClipAppendagePoses? {
            switch self {
            case .none:
                return nil
            case .rearBodyEstimateOrStoredArtifact:
                guard
                    context.captureMode == .rearBody3D,
                    let clip
                else {
                    return nil
                }

                if context.sourceClip == nil,
                   let storedPoses,
                   storedPoses.frames.count == clip.frames.count {
                    return storedPoses
                }

                guard clip.frames.first?.jointPositions.count == OdoroSkeletonDefinition.jointCount else {
                    return nil
                }

                return appendagePoseEstimator.estimatePoses(for: clip)
            }
        }
    }

    private enum CameraPresetStrategy {
        case none
        case estimate
        case storedArtifactOrEstimate

        nonisolated
        func resolve(
            clip: MotionClip?,
            storedPreset: StagePlaybackCameraPreset?,
            cameraEstimator: StagePlaybackCameraEstimator
        ) -> StagePlaybackCameraPreset? {
            switch self {
            case .none:
                return nil
            case .estimate:
                guard let clip else {
                    return nil
                }

                return cameraEstimator.estimate(for: clip)
            case .storedArtifactOrEstimate:
                if let storedPreset {
                    return storedPreset
                }

                guard let clip else {
                    return nil
                }

                return cameraEstimator.estimate(for: clip)
            }
        }
    }

    private struct VariantRecipe {
        let definition: ClipVariantDefinition
        let clipPlan: VariantClipPlan
        let outputPolicy: VariantOutputPolicy

        nonisolated static func display(
            _ definition: ClipVariantDefinition,
            clipPlan: VariantClipPlan,
            outputPolicy: VariantOutputPolicy
        ) -> Self {
            Self(
                definition: definition,
                clipPlan: clipPlan,
                outputPolicy: outputPolicy
            )
        }

        nonisolated static func avatarRig(
            _ definition: ClipVariantDefinition,
            clipPlan: VariantClipPlan,
            outputPolicy: VariantOutputPolicy
        ) -> Self {
            Self(
                definition: definition,
                clipPlan: clipPlan,
                outputPolicy: outputPolicy
            )
        }

        nonisolated static let displayRaw = Self.display(
            StagePreparedPlaybackVariantCatalog.displayRaw,
            clipPlan: .sourceOrPlayback([.rebaseForStage]),
            outputPolicy: .rawDisplay
        )

        nonisolated static let displayCanonical = Self.display(
            StagePreparedPlaybackVariantCatalog.displayCanonical,
            clipPlan: .sourceOrPlayback([.canonicalizeForPlayback, .rebaseForStage]),
            outputPolicy: .canonicalDisplay
        )

        nonisolated static let displayStabilized = Self.display(
            StagePreparedPlaybackVariantCatalog.displayStabilized,
            clipPlan: .playback(),
            outputPolicy: .stabilizedDisplay
        )

        nonisolated static let avatarRigStabilized = Self.avatarRig(
            StagePreparedPlaybackVariantCatalog.avatarRigStabilized,
            clipPlan: .source([.rigNormalizeForStage]),
            outputPolicy: .avatarRigStabilized
        )

        nonisolated static let all = [
            displayRaw,
            displayCanonical,
            displayStabilized,
            avatarRigStabilized,
        ]
    }

    private struct VariantOutputPolicy {
        let skeletonDefinitionPolicy: SkeletonDefinitionPolicy
        let integrityPolicy: IntegrityPolicy
        let stabilizationProfile: MotionClipStageStabilizer.Profile?
        let artifactSlot: VariantArtifactSlot?
        let appendagePoseStrategy: AppendagePoseStrategy
        let cameraPresetStrategy: CameraPresetStrategy

        nonisolated static let rawDisplay = Self(
            skeletonDefinitionPolicy: .rawDisplayFallback,
            integrityPolicy: .rawDisplayFallback,
            stabilizationProfile: nil,
            artifactSlot: .raw,
            appendagePoseStrategy: .none,
            cameraPresetStrategy: .storedArtifactOrEstimate
        )

        nonisolated static let canonicalDisplay = Self(
            skeletonDefinitionPolicy: .odoroCanonical,
            integrityPolicy: .fixed(.displaySafe),
            stabilizationProfile: nil,
            artifactSlot: .canonical,
            appendagePoseStrategy: .rearBodyEstimateOrStoredArtifact,
            cameraPresetStrategy: .storedArtifactOrEstimate
        )

        nonisolated static let stabilizedDisplay = Self(
            skeletonDefinitionPolicy: .deriveFromClip,
            integrityPolicy: .fixed(.displaySafe),
            stabilizationProfile: .displaySafe,
            artifactSlot: .stabilized,
            appendagePoseStrategy: .rearBodyEstimateOrStoredArtifact,
            cameraPresetStrategy: .storedArtifactOrEstimate
        )

        nonisolated static let avatarRigStabilized = Self(
            skeletonDefinitionPolicy: .source,
            integrityPolicy: .fixed(.rigSafe),
            stabilizationProfile: .rigSafe,
            artifactSlot: nil,
            appendagePoseStrategy: .none,
            cameraPresetStrategy: .estimate
        )
    }

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
        hints: MotionPlaybackHints? = nil
    ) -> StagePreparedPlayback {
        let context = VariantBuildContext(
            sourceClip: sourceClip,
            playbackClip: playbackClip,
            captureMode: captureMode,
            hints: hints
        )

        let variants = VariantRecipe.all.compactMap { recipe in
            buildVariant(from: recipe, context: context)
        }

        return StagePreparedPlayback(variants: variants)
    }

    nonisolated private func buildVariant(
        from recipe: VariantRecipe,
        context: VariantBuildContext
    ) -> ClipVariant? {
        let clip = recipe.clipPlan.resolve(in: context)
        if recipe.definition.key.purpose == .avatarRig,
           clip == nil {
            return nil
        }

        let storedArtifacts = recipe.outputPolicy.artifactSlot?.storedArtifacts(in: context)
        let appendagePoses = recipe.outputPolicy.appendagePoseStrategy.resolve(
            clip: clip,
            storedPoses: storedArtifacts?.appendagePoses,
            context: context,
            appendagePoseEstimator: appendagePoseEstimator
        )

        return ClipVariant(
            purpose: recipe.definition.key.purpose,
            processingStage: recipe.definition.key.processingStage,
            clip: clip,
            appendagePoses: appendagePoses,
            cameraPreset: recipe.outputPolicy.cameraPresetStrategy.resolve(
                clip: clip,
                storedPreset: storedArtifacts?.cameraPreset,
                cameraEstimator: cameraEstimator
            ),
            skeletonDefinition: recipe.outputPolicy.skeletonDefinitionPolicy.resolve(
                clip: clip,
                context: context,
                inferredSkeletonDefinition: inferredSkeletonDefinition(for:)
            ),
            integrity: recipe.outputPolicy.integrityPolicy.resolve(in: context),
            stabilizationProfile: recipe.outputPolicy.stabilizationProfile
        )
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

        if let headForward = headForward(in: frame),
           simd_dot(forward, headForward) < 0 {
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

    nonisolated func headForward(in frame: MotionFrame) -> SIMD3<Float>? {
        let candidates = [
            horizontalDirection(from: canonicalPosition(for: .chest, in: frame), to: canonicalPosition(for: .head, in: frame)),
            horizontalDirection(from: canonicalPosition(for: .root, in: frame), to: canonicalPosition(for: .head, in: frame)),
            horizontalDirection(from: canonicalPosition(for: .root, in: frame), to: canonicalPosition(for: .neck, in: frame)),
        ].compactMap { $0 }

        guard !candidates.isEmpty else {
            return nil
        }

        return normalizedOrNil(candidates.reduce(.zero, +))
    }

    nonisolated private func horizontalDirection(from start: SIMD3<Float>?, to end: SIMD3<Float>?) -> SIMD3<Float>? {
        guard let start, let end else {
            return nil
        }

        return normalizedOrNil(SIMD3<Float>(end.x - start.x, 0, end.z - start.z))
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
