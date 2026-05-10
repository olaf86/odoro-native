//
//  StagePlaybackRenderer.swift
//  Odoro
//

import ARKit
import Foundation
import os
import RealityKit
import UIKit

@MainActor
final class StagePlaybackRenderer: NSObject {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "StagePlaybackRenderer")
    nonisolated private static let stageCameraNearPlane: Float = 0.1
    nonisolated private static let stageCameraFarPlane: Float = 20
    nonisolated private static let stageCameraFieldOfViewDegrees: Float = 60
    nonisolated private static let defaultStageLookAt = SIMD3<Float>(0, 0.95, 0)
    nonisolated private static let defaultStageCameraPosition = SIMD3<Float>(0, 1.35, 3.4)
    private enum StageFloorStyle {
        nonisolated static let extent: Float = 8.0
        nonisolated static let inset: Float = 0.28
        nonisolated static let lineThickness: Float = 0.003
        nonisolated static let lineCenterY: Float = lineThickness * 0.5
        nonisolated static let minorSpacing: Float = 0.25
        nonisolated static let majorSpacing: Float = 1.0
        nonisolated static let majorLineWidth: Float = 0.028
        nonisolated static let minorLineWidth: Float = 0.01
        nonisolated static let majorLineColor = UIColor(red: 0.5, green: 0.92, blue: 1.0, alpha: 0.88)
        nonisolated static let minorLineColor = UIColor(red: 0.4, green: 0.8, blue: 0.95, alpha: 0.4)
    }
    enum SkeletonDebugLayout: Equatable {
        case rawARKit
        case canonical
        case canonicalTorso
    }

    private struct RawRenderJoint {
        let jointName: ARSkeleton.JointName
        let fallbackRawName: String?
    }

    private struct RenderLimb {
        let startIndex: Int
        let endIndex: Int
    }

    private let skeletonDefinition = ARSkeletonDefinition.defaultBody3D
    private let poseSampler = AvatarPoseSampler()
    private let canonicalRenderJointNames: [OdoroJointName] = [
        .root,
        .spine,
        .chest,
        .neck,
        .head,
        .leftShoulder,
        .rightShoulder,
        .leftUpperArm,
        .rightUpperArm,
        .leftElbow,
        .rightElbow,
        .leftWrist,
        .rightWrist,
        .leftHip,
        .rightHip,
        .leftKnee,
        .rightKnee,
        .leftAnkle,
        .rightAnkle,
        .leftFoot,
        .rightFoot,
    ]
    private let canonicalTorsoRenderJointNames: [OdoroJointName] = [
        .root,
        .spine,
        .chest,
        .neck,
        .head,
    ]
    private let canonicalRenderLimbs: [RenderLimb] = [
        .init(startIndex: 0, endIndex: 1),
        .init(startIndex: 1, endIndex: 2),
        .init(startIndex: 2, endIndex: 3),
        .init(startIndex: 3, endIndex: 4),
        .init(startIndex: 2, endIndex: 5),
        .init(startIndex: 2, endIndex: 6),
        .init(startIndex: 5, endIndex: 7),
        .init(startIndex: 7, endIndex: 9),
        .init(startIndex: 9, endIndex: 11),
        .init(startIndex: 6, endIndex: 8),
        .init(startIndex: 8, endIndex: 10),
        .init(startIndex: 10, endIndex: 12),
        .init(startIndex: 0, endIndex: 13),
        .init(startIndex: 0, endIndex: 14),
        .init(startIndex: 13, endIndex: 15),
        .init(startIndex: 14, endIndex: 16),
        .init(startIndex: 15, endIndex: 17),
        .init(startIndex: 16, endIndex: 18),
        .init(startIndex: 17, endIndex: 19),
        .init(startIndex: 18, endIndex: 20),
    ]
    private let canonicalTorsoRenderLimbs: [RenderLimb] = [
        .init(startIndex: 0, endIndex: 1),
        .init(startIndex: 1, endIndex: 2),
        .init(startIndex: 2, endIndex: 3),
        .init(startIndex: 3, endIndex: 4),
    ]
    private let rawRenderJoints: [RawRenderJoint] = [
        .init(jointName: .root, fallbackRawName: "hips_joint"),
        .init(jointName: .head, fallbackRawName: "head_joint"),
        .init(jointName: .leftShoulder, fallbackRawName: "left_shoulder_1_joint"),
        .init(jointName: .rightShoulder, fallbackRawName: "right_shoulder_1_joint"),
        .init(jointName: ARSkeleton.JointName(rawValue: "left_arm_joint"), fallbackRawName: nil),
        .init(jointName: ARSkeleton.JointName(rawValue: "right_arm_joint"), fallbackRawName: nil),
        .init(jointName: ARSkeleton.JointName(rawValue: "left_forearm_joint"), fallbackRawName: nil),
        .init(jointName: ARSkeleton.JointName(rawValue: "right_forearm_joint"), fallbackRawName: nil),
        .init(jointName: .leftHand, fallbackRawName: "left_hand_joint"),
        .init(jointName: .rightHand, fallbackRawName: "right_hand_joint"),
        .init(jointName: ARSkeleton.JointName(rawValue: "left_upLeg_joint"), fallbackRawName: nil),
        .init(jointName: ARSkeleton.JointName(rawValue: "right_upLeg_joint"), fallbackRawName: nil),
        .init(jointName: ARSkeleton.JointName(rawValue: "left_leg_joint"), fallbackRawName: nil),
        .init(jointName: ARSkeleton.JointName(rawValue: "right_leg_joint"), fallbackRawName: nil),
        .init(jointName: .leftFoot, fallbackRawName: "left_foot_joint"),
        .init(jointName: .rightFoot, fallbackRawName: "right_foot_joint"),
    ]
    private let rawRenderLimbs: [RenderLimb] = [
        .init(startIndex: 0, endIndex: 1),
        .init(startIndex: 0, endIndex: 2),
        .init(startIndex: 0, endIndex: 3),
        .init(startIndex: 2, endIndex: 4),
        .init(startIndex: 4, endIndex: 6),
        .init(startIndex: 6, endIndex: 8),
        .init(startIndex: 3, endIndex: 5),
        .init(startIndex: 5, endIndex: 7),
        .init(startIndex: 7, endIndex: 9),
        .init(startIndex: 0, endIndex: 10),
        .init(startIndex: 0, endIndex: 11),
        .init(startIndex: 10, endIndex: 12),
        .init(startIndex: 12, endIndex: 14),
        .init(startIndex: 11, endIndex: 13),
        .init(startIndex: 13, endIndex: 15),
    ]

    private weak var view: ARView?
    private var clip: MotionClip?
    private var rigClip: MotionClip?
    private var appendagePoses: MotionClipAppendagePoses?
    private var stageCameraPreset: StagePlaybackCameraPreset?
    private var playbackTimer: Timer?
    private var playbackStartedAt: Date?
    private var usesProceduralMockPlayback = false
    private var currentAvatarOption = AvatarCatalog.defaultOption

    private var stageAnchor = AnchorEntity()
    private var stageCameraEntity = Entity()
    private var dancerRoot = Entity()
    private var jointEntities: [ModelEntity] = []
    private var limbEntities: [ModelEntity] = []
    private var footDirectionEntities: [ModelEntity] = []

    private var characterEntity: Entity?
    private var skeletalModelEntity: ModelEntity?
    private var skeletalBindPoseTransforms: [Transform] = []
    private var precomputedRigFrames: [[Transform]]?
    private var activeRigProfile: AvatarRigProfile?
    private var hasStoppedBuiltInAnimation = false
    private var skeletonDebugLayout: SkeletonDebugLayout = .canonical
    private var avatarLoadTask: Task<Void, Never>?

    override init() {
        super.init()
        reloadAvatarAsset()
    }

    func attach(to view: ARView) {
        self.view = view
        configureScene(in: view)
        if let clip, let firstFrame = clip.frames.first {
            render(frame: firstFrame, frameIndex: 0)
        }
    }

    func setClip(_ clip: MotionClip?) {
        self.clip = clip
        precomputedRigFrames = nil
        precomputeRigFramesIfReady()

        if let firstFrame = clip?.frames.first, !jointEntities.isEmpty, !limbEntities.isEmpty {
            render(frame: firstFrame, frameIndex: 0)
        }
    }

    func setRigClip(_ clip: MotionClip?) {
        rigClip = clip
        precomputedRigFrames = nil
        precomputeRigFramesIfReady()

        if let currentClip = self.clip, let firstFrame = currentClip.frames.first {
            render(frame: firstFrame, frameIndex: 0)
        }
    }

    func setAppendagePoses(_ poses: MotionClipAppendagePoses?) {
        appendagePoses = poses

        if let clip, let firstFrame = clip.frames.first {
            render(frame: firstFrame, frameIndex: 0)
        } else {
            footDirectionEntities.forEach { $0.isEnabled = false }
        }
    }

    func setStageCameraPreset(_ preset: StagePlaybackCameraPreset?) {
        guard stageCameraPreset != preset else {
            return
        }

        stageCameraPreset = preset
        updateStageCameraTransform()
    }

    func setUsesProceduralMockPlayback(_ usesProceduralMockPlayback: Bool) {
        self.usesProceduralMockPlayback = usesProceduralMockPlayback
    }

    func setSkeletonDebugLayout(_ layout: SkeletonDebugLayout) {
        guard skeletonDebugLayout != layout else {
            return
        }

        let wasPlaying = playbackTimer != nil
        skeletonDebugLayout = layout

        if let view {
            configureScene(in: view)
            if let firstFrame = clip?.frames.first {
                render(frame: firstFrame, frameIndex: 0)
            }
            if wasPlaying {
                play()
            }
        }
    }

    func setAvatarOption(_ avatarOption: StageAvatarOption) {
        guard self.currentAvatarOption != avatarOption else {
            return
        }

        currentAvatarOption = avatarOption
        reloadAvatarAsset()

        if let view {
            configureScene(in: view)
            if let firstFrame = clip?.frames.first {
                render(frame: firstFrame, frameIndex: 0)
            }
        }
    }

    // MARK: - Character model loading

    private func reloadAvatarAsset() {
        avatarLoadTask?.cancel()
        avatarLoadTask = nil
        characterEntity = nil
        skeletalModelEntity = nil
        skeletalBindPoseTransforms = []
        precomputedRigFrames = nil
        activeRigProfile = nil

        guard
            currentAvatarOption.selection.kind == .avatar,
            currentAvatarOption.isReadyForPlayback
        else {
            return
        }

        do {
            if let runtimeAssetURL = currentAvatarOption.runtimeAssetURL {
                let expectedSelection = currentAvatarOption.selection
                let rigProfile = currentAvatarOption.rigProfile
                if #available(iOS 18.0, *) {
                    avatarLoadTask = Task { @MainActor [weak self] in
                        guard let self else { return }
                        do {
                            let entity = try await Entity(contentsOf: runtimeAssetURL)
                            guard !Task.isCancelled, self.currentAvatarOption.selection == expectedSelection else {
                                return
                            }

                            self.setLoadedAvatarEntity(
                                entity,
                                assetName: runtimeAssetURL.lastPathComponent,
                                rigProfile: rigProfile
                            )
                        } catch is CancellationError {
                            return
                        } catch {
                            Self.logger.error("Failed to load installed avatar asset from '\(runtimeAssetURL.lastPathComponent)': \(error)")
                        }
                    }
                } else {
                    let entity = try Entity.load(contentsOf: runtimeAssetURL)
                    guard currentAvatarOption.selection == expectedSelection else {
                        return
                    }

                    setLoadedAvatarEntity(
                        entity,
                        assetName: runtimeAssetURL.lastPathComponent,
                        rigProfile: rigProfile
                    )
                }
                return
            } else if let resourceName = currentAvatarOption.runtimeAssetResourceName {
                let entity = try Entity.load(named: resourceName)
                setLoadedAvatarEntity(
                    entity,
                    assetName: resourceName,
                    rigProfile: currentAvatarOption.rigProfile
                )
            } else {
                return
            }
        } catch {
            Self.logger.error("Failed to load avatar asset: \(error)")
        }
    }

    private func setLoadedAvatarEntity(
        _ entity: Entity,
        assetName: String,
        rigProfile: AvatarRigProfile?
    ) {
        characterEntity = entity
        skeletalModelEntity = findSkeletalModelEntity(entity)
        skeletalBindPoseTransforms = skeletalModelEntity?.jointTransforms ?? []
        activeRigProfile = rigProfile
        let animCount = entity.availableAnimations.count
        let bindingCount = activeRigProfile?.bindings.count ?? 0
        let jointCount = skeletalModelEntity?.jointNames.count ?? 0
        Self.logger.info("avatar loaded — asset: \(assetName), skeletal model: \(self.skeletalModelEntity != nil), joints: \(jointCount), bindings: \(bindingCount), animations: \(animCount)")
        precomputeRigFramesIfReady()

        if let view {
            let wasPlaying = playbackTimer != nil
            configureScene(in: view)
            if let firstFrame = clip?.frames.first {
                render(frame: firstFrame, frameIndex: 0)
            }
            if wasPlaying {
                play()
            }
        }
    }

    private func logEntityTransforms(_ entity: Entity, depth: Int) {
        let indent = String(repeating: "  ", count: depth)
        let p = entity.position
        let s = entity.scale
        let isModel = entity is ModelEntity
        Self.logger.debug("\(indent)'\(entity.name)' \(isModel ? "[Model]" : "") pos=(\(p.x, format: .fixed(precision: 3)),\(p.y, format: .fixed(precision: 3)),\(p.z, format: .fixed(precision: 3))) scale=(\(s.x, format: .fixed(precision: 3)),\(s.y, format: .fixed(precision: 3)),\(s.z, format: .fixed(precision: 3)))")
        for child in entity.children {
            logEntityTransforms(child, depth: depth + 1)
        }
    }

    private func findSkeletalModelEntity(_ entity: Entity) -> ModelEntity? {
        if let modelEntity = entity as? ModelEntity, !modelEntity.jointNames.isEmpty {
            return modelEntity
        }

        for child in entity.children {
            if let found = findSkeletalModelEntity(child) { return found }
        }

        return findModelEntity(entity)
    }

    private func findModelEntity(_ entity: Entity) -> ModelEntity? {
        if let modelEntity = entity as? ModelEntity {
            return modelEntity
        }

        for child in entity.children {
            if let found = findModelEntity(child) {
                return found
            }
        }

        return nil
    }

    func play() {
        guard let clip, !clip.isEmpty else { return }

        pause()
        render(frame: clip.frames[0], frameIndex: 0)
        playbackStartedAt = Date()

        playbackTimer = Timer.scheduledTimer(
            timeInterval: 1 / 30,
            target: self,
            selector: #selector(handlePlaybackTimer),
            userInfo: nil,
            repeats: true
        )
    }

    func pause() {
        playbackTimer?.invalidate()
        playbackTimer = nil
        playbackStartedAt = nil
    }

    private func configureScene(in view: ARView) {
        pause()
        precomputedRigFrames = nil

        view.backgroundColor = UIColor(red: 0.03, green: 0.03, blue: 0.06, alpha: 1)
        view.scene.anchors.removeAll()

        stageAnchor = AnchorEntity()
        stageCameraEntity = Entity()
        dancerRoot = Entity()
        jointEntities.removeAll()
        limbEntities.removeAll()
        footDirectionEntities.removeAll()

        let stageFloor = makeStageFloorEntity()
        stageFloor.position = .zero
        stageAnchor.addChild(stageFloor)

        buildDancerHierarchy()
        stageAnchor.addChild(dancerRoot)

        stageCameraEntity.components.set(Self.makeStageCameraComponent())
        updateStageCameraTransform()
        stageAnchor.addChild(stageCameraEntity)

        view.scene.addAnchor(stageAnchor)
    }

    private func makeStageFloorEntity() -> Entity {
        let root = Entity()
        let gridExtent = StageFloorStyle.extent - (StageFloorStyle.inset * 2)

        for position in stride(from: -gridExtent * 0.5, through: gridExtent * 0.5, by: StageFloorStyle.minorSpacing) {
            let isMajor = isApproximatelyMultiple(position, of: StageFloorStyle.majorSpacing)
            let lineWidth = isMajor ? StageFloorStyle.majorLineWidth : StageFloorStyle.minorLineWidth
            let lineColor = isMajor ? StageFloorStyle.majorLineColor : StageFloorStyle.minorLineColor
            let material = UnlitMaterial(color: lineColor)

            let depthLine = ModelEntity(
                mesh: .generateBox(size: [lineWidth, StageFloorStyle.lineThickness, gridExtent]),
                materials: [material]
            )
            depthLine.position = [position, StageFloorStyle.lineCenterY, 0]
            root.addChild(depthLine)

            let widthLine = ModelEntity(
                mesh: .generateBox(size: [gridExtent, StageFloorStyle.lineThickness, lineWidth]),
                materials: [material]
            )
            widthLine.position = [0, StageFloorStyle.lineCenterY, position]
            root.addChild(widthLine)
        }

        return root
    }

    private func isApproximatelyMultiple(_ value: Float, of divisor: Float) -> Bool {
        guard divisor != 0 else {
            return false
        }

        let ratio = value / divisor
        return abs(ratio.rounded() - ratio) < 0.001
    }

    nonisolated static func makeStageCameraComponent() -> PerspectiveCameraComponent {
        // The playback stage is a compact scene. A finite frustum with a slightly
        // larger near plane preserves depth precision so distant skinned meshes do
        // not lose body parts from z-buffer instability.
        PerspectiveCameraComponent(
            near: stageCameraNearPlane,
            far: stageCameraFarPlane,
            fieldOfViewInDegrees: stageCameraFieldOfViewDegrees
        )
    }

    private func updateStageCameraTransform() {
        let lookAt = stageCameraPreset?.lookAtSIMD ?? Self.defaultStageLookAt
        let position = stageCameraPreset?.positionSIMD ?? Self.defaultStageCameraPosition
        stageCameraEntity.look(at: lookAt, from: position, relativeTo: nil)
    }

    private var activeRenderLimbs: [RenderLimb] {
        switch skeletonDebugLayout {
        case .rawARKit:
            rawRenderLimbs
        case .canonical:
            canonicalRenderLimbs
        case .canonicalTorso:
            canonicalTorsoRenderLimbs
        }
    }

    private var activeRenderJointCount: Int {
        switch skeletonDebugLayout {
        case .rawARKit:
            rawRenderJoints.count
        case .canonical:
            canonicalRenderJointNames.count
        case .canonicalTorso:
            canonicalTorsoRenderJointNames.count
        }
    }

    private var activeCanonicalRenderJointNames: [OdoroJointName] {
        switch skeletonDebugLayout {
        case .rawARKit:
            []
        case .canonical:
            canonicalRenderJointNames
        case .canonicalTorso:
            canonicalTorsoRenderJointNames
        }
    }

    private func buildDancerHierarchy() {
        hasStoppedBuiltInAnimation = false

        // Character model takes priority over the procedural skeleton
        // whenever the entity loaded, even if individual joints are not yet mapped.
        let hasCharacter = characterEntity != nil && currentAvatarOption.selection.kind == .avatar

        if hasCharacter, let character = characterEntity {
            character.removeFromParent()
            let scale = activeRigProfile?.scaleCompensation ?? 1
            let floorOffset = activeRigProfile?.floorOffset ?? 0
            character.scale = SIMD3<Float>(repeating: scale)
            character.position = SIMD3<Float>(0, floorOffset, 0)
            dancerRoot.addChild(character)
            logEntityTransforms(character, depth: 0)

            // Play any built-in animation embedded in the USDZ (idle loop, etc.).
            // This serves as a rendering path before live joint transforms are available.
            if let animation = character.availableAnimations.first {
                character.playAnimation(animation.repeat(duration: .infinity))
                Self.logger.debug("Playing built-in character animation")
            } else if #available(iOS 18.0, *), let modelEntity = skeletalModelEntity {
                // No built-in animation. USD Skeleton skinned meshes may not produce any
                // rendered output until the deformation pipeline is activated. Setting an
                // empty SkeletalPosesComponent is enough to trigger it so the bind pose renders.
                if modelEntity.components[SkeletalPosesComponent.self] == nil {
                    modelEntity.components[SkeletalPosesComponent.self] = SkeletalPosesComponent(poses: [])
                }
            }
        }

        for _ in 0..<activeRenderJointCount {
            let joint = ModelEntity(
                mesh: .generateSphere(radius: 0.045),
                materials: [UnlitMaterial(color: UIColor(red: 1, green: 0.33, blue: 0.48, alpha: 1))]
            )
            joint.isEnabled = !hasCharacter
            jointEntities.append(joint)
            dancerRoot.addChild(joint)
        }

        for _ in activeRenderLimbs {
            let limbMesh: MeshResource
            if #available(iOS 18.0, *) {
                limbMesh = .generateCylinder(height: 1.0, radius: 0.025)
            } else {
                limbMesh = .generateBox(size: [0.05, 1.0, 0.05])
            }
            let limb = ModelEntity(
                mesh: limbMesh,
                materials: [UnlitMaterial(color: UIColor(red: 0.38, green: 0.89, blue: 0.86, alpha: 1))]
            )
            limb.isEnabled = !hasCharacter
            limbEntities.append(limb)
            dancerRoot.addChild(limb)
        }

        for _ in 0..<2 {
            let directionMesh: MeshResource
            if #available(iOS 18.0, *) {
                directionMesh = .generateCylinder(height: 1.0, radius: 0.012)
            } else {
                directionMesh = .generateBox(size: [0.024, 1.0, 0.024])
            }

            let direction = ModelEntity(
                mesh: directionMesh,
                materials: [UnlitMaterial(color: UIColor(red: 1.0, green: 0.82, blue: 0.28, alpha: 0.95))]
            )
            direction.isEnabled = false
            footDirectionEntities.append(direction)
            dancerRoot.addChild(direction)
        }
    }

    @objc private func handlePlaybackTimer() {
        guard
            let clip,
            let playbackStartedAt,
            clip.duration > 0
        else {
            return
        }

        let elapsed = Date().timeIntervalSince(playbackStartedAt).truncatingRemainder(dividingBy: clip.duration)
        let frameIndex = clip.frames.lastIndex(where: { $0.time <= elapsed }) ?? 0
        let frame = clip.frames[frameIndex]
        render(frame: frame, frameIndex: frameIndex)
    }

    private func render(frame: MotionFrame, frameIndex: Int) {
        if currentAvatarOption.selection.kind == .avatar, characterEntity != nil {
            renderFootDirections(frameIndex: frameIndex, isVisible: false)
            if let rigIndex = resolvedRigFrameIndex(for: frame, displayFrameIndex: frameIndex),
               renderCharacter(rigFrameIndex: rigIndex) {
                return
            }

            let fallbackFrame = resolvedAvatarRigFrame(for: frame, frameIndex: frameIndex)
            if fallbackFrame.jointPositions.contains(where: Self.isValidMotionPosition) {
                // Front-camera or other source: real positions available but no rotations.
                renderCharacterAtRoot(frame: fallbackFrame)
            } else {
                // Simulator / MockMotionSource: all positions invalid (y = -10).
                // Drive the skeleton procedurally so the character animates.
                renderCharacterFallback(frame: fallbackFrame)
            }
            return
        }

        var jointPositions = resolvedJointPositions(from: frame)
        let renderLimbs = activeRenderLimbs
        guard jointEntities.count == jointPositions.count, limbEntities.count == renderLimbs.count else {
            return
        }

        if shouldUseProceduralFallback(for: jointPositions) {
            let fallbackPositions = fallbackJointPositions(for: frame)
            guard fallbackPositions.count == jointEntities.count else {
                assertionFailure("Fallback joint count (\(fallbackPositions.count)) did not match active render joint count (\(jointEntities.count)).")
                return
            }
            jointPositions = fallbackPositions.map(Optional.some)
        }

        for (index, position) in jointPositions.enumerated() {
            let jointEntity = jointEntities[index]
            if let position {
                jointEntity.position = position
                jointEntity.isEnabled = true
            } else {
                jointEntity.isEnabled = false
            }
        }

        for (index, limb) in renderLimbs.enumerated() {
            let limbEntity = limbEntities[index]
            guard
                jointPositions.indices.contains(limb.startIndex),
                jointPositions.indices.contains(limb.endIndex),
                let start = jointPositions[limb.startIndex],
                let end = jointPositions[limb.endIndex]
            else {
                limbEntity.isEnabled = false
                continue
            }

            let delta = end - start
            let length = simd_length(delta)
            guard length > 0.0001 else {
                limbEntity.isEnabled = false
                continue
            }

            limbEntity.isEnabled = true
            limbEntity.position = (start + end) * 0.5
            limbEntity.orientation = simd_quatf(from: SIMD3<Float>(0, 1, 0), to: simd_normalize(delta))
            limbEntity.scale = [1, length, 1]
        }

        renderFootDirections(frameIndex: frameIndex, isVisible: skeletonDebugLayout == .canonical)
    }

    private func resolvedAvatarRigFrame(for displayFrame: MotionFrame, frameIndex: Int) -> MotionFrame {
        guard let rigClip else {
            return displayFrame
        }

        if rigClip.frames.indices.contains(frameIndex) {
            return rigClip.frames[frameIndex]
        }

        let matchedIndex = rigClip.frames.lastIndex(where: { $0.time <= displayFrame.time }) ?? 0
        guard rigClip.frames.indices.contains(matchedIndex) else {
            return displayFrame
        }

        return rigClip.frames[matchedIndex]
    }

    // Returns the index into precomputedRigFrames for a given display frame.
    // Mirrors the resolvedAvatarRigFrame lookup so the two stay in sync.
    private func resolvedRigFrameIndex(for displayFrame: MotionFrame, displayFrameIndex: Int) -> Int? {
        guard let precomputedRigFrames, !precomputedRigFrames.isEmpty else {
            return nil
        }

        if precomputedRigFrames.indices.contains(displayFrameIndex) {
            return displayFrameIndex
        }

        let sourceClip = rigClip ?? clip
        return sourceClip?.frames.lastIndex(where: { $0.time <= displayFrame.time })
    }

    // MARK: - Rig frame pre-computation

    private func precomputeRigFramesIfReady() {
        let sourceClip = rigClip ?? clip
        guard
            let sourceClip,
            let modelEntity = skeletalModelEntity,
            let rigProfile = activeRigProfile
        else { return }

        precomputedRigFrames = buildRigFrames(
            clip: sourceClip,
            modelEntity: modelEntity,
            rigProfile: rigProfile
        )
        Self.logger.debug("Precomputed rig frames: \(self.precomputedRigFrames?.count ?? 0) frames")
    }

    private func buildRigFrames(
        clip: MotionClip,
        modelEntity: ModelEntity,
        rigProfile: AvatarRigProfile
    ) -> [[Transform]] {
        let bindPoseTransforms = skeletalBindPoseTransforms.count == modelEntity.jointTransforms.count
            ? skeletalBindPoseTransforms
            : modelEntity.jointTransforms
        guard !bindPoseTransforms.isEmpty else { return [] }

        // USD skeletons store joint names as hierarchical paths (e.g. "root/J_Bip_C_Hips"),
        // while rig profiles authored from GLB use just the leaf name ("J_Bip_C_Hips").
        // Index both the full path and the leaf component so either form resolves.
        var modelJointIndices: [String: Int] = [:]
        for (index, name) in modelEntity.jointNames.enumerated() {
            modelJointIndices[name] = index
            let leaf = name.components(separatedBy: "/").last ?? name
            if leaf != name {
                modelJointIndices[leaf] = modelJointIndices[leaf] ?? index
            }
        }

        let retargeter = AvatarRigRetargeter(
            profile: rigProfile,
            bindPoseTransforms: bindPoseTransforms,
            modelJointIndices: modelJointIndices,
            tPose: poseSampler.tPose
        )

        var result: [[Transform]] = []
        result.reserveCapacity(clip.frames.count)
        var previousTransforms: [Transform]? = nil

        for frame in clip.frames {
            let pose = poseSampler.pose(from: frame)
            let transforms = retargeter.retargetFrame(pose, previousTransforms: previousTransforms)
            result.append(transforms)
            previousTransforms = transforms
        }

        return result
    }

    private func renderFootDirections(frameIndex: Int, isVisible: Bool) {
        guard
            isVisible,
            let appendagePoses,
            appendagePoses.frames.indices.contains(frameIndex),
            footDirectionEntities.count == 2
        else {
            footDirectionEntities.forEach { $0.isEnabled = false }
            return
        }

        let footPoses = appendagePoses.frames[frameIndex].feet
        let poses: [(AppendagePose?, Float)] = [
            (footPoses.left, footPoses.leftContactWeight),
            (footPoses.right, footPoses.rightContactWeight),
        ]

        for (index, item) in poses.enumerated() {
            let entity = footDirectionEntities[index]
            guard let pose = item.0 else {
                entity.isEnabled = false
                continue
            }

            let length = 0.16 + item.1 * 0.06
            let delta = pose.forward * length
            let magnitude = simd_length(delta)
            guard magnitude > 0.0001 else {
                entity.isEnabled = false
                continue
            }

            entity.isEnabled = true
            entity.position = pose.pivot + delta * 0.5
            entity.orientation = simd_quatf(from: SIMD3<Float>(0, 1, 0), to: simd_normalize(delta))
            entity.scale = [1, magnitude, 1]
        }
    }

    private func resolvedJointPositions(from frame: MotionFrame) -> [SIMD3<Float>?] {
        switch skeletonDebugLayout {
        case .rawARKit:
            return rawRenderJoints.map { renderJoint in
                resolvedPosition(
                    for: renderJoint.jointName,
                    fallbackRawName: renderJoint.fallbackRawName,
                    in: frame
                )
            }
        case .canonical, .canonicalTorso:
            let canonicalPositions = canonicalJointPositions(from: frame)

            return activeCanonicalRenderJointNames.map { jointName in
                let index = OdoroSkeletonDefinition.index(of: jointName)
                guard canonicalPositions.indices.contains(index) else {
                    return nil
                }

                let position = canonicalPositions[index]
                guard Self.isValidMotionPosition(position) else {
                    return nil
                }

                return position
            }
        }
    }

    private func canonicalJointPositions(from frame: MotionFrame) -> [SIMD3<Float>] {
        if frame.jointPositions.count == OdoroSkeletonDefinition.jointCount {
            return frame.jointPositions
        }

        return OdoroCanonicalPoseMapper
            .map(frame: frame)
            .positions
            .map(\.simdValue)
    }

    private func canonicalPosition(for jointName: OdoroJointName, in frame: MotionFrame) -> SIMD3<Float>? {
        guard frame.jointPositions.count == OdoroSkeletonDefinition.jointCount else {
            return nil
        }

        let index = OdoroSkeletonDefinition.index(of: jointName)
        guard frame.jointPositions.indices.contains(index) else {
            return nil
        }

        let position = frame.jointPositions[index]
        guard position.x.isFinite, position.y.isFinite, position.z.isFinite, position.y > -5 else {
            return nil
        }

        return position
    }

    private func shouldUseProceduralFallback(for jointPositions: [SIMD3<Float>?]) -> Bool {
        if usesProceduralMockPlayback {
            return true
        }

        let resolved = jointPositions.compactMap { $0 }
        guard resolved.count >= 6 else {
            return true
        }

        let xs = resolved.map(\.x)
        let ys = resolved.map(\.y)
        let zs = resolved.map(\.z)

        guard
            let minX = xs.min(),
            let maxX = xs.max(),
            let minY = ys.min(),
            let maxY = ys.max(),
            let minZ = zs.min(),
            let maxZ = zs.max()
        else {
            return true
        }

        let width = maxX - minX
        let height = maxY - minY
        let depth = maxZ - minZ

        return width > 3 || height > 3.5 || depth > 3 || maxY < 0.4 || minY < -1.2
    }

    private func resolvedPosition(
        for jointName: ARSkeleton.JointName,
        fallbackRawName: String? = nil,
        in frame: MotionFrame
    ) -> SIMD3<Float>? {
        if let position = position(for: jointName, in: frame) {
            return position
        }

        guard let fallbackRawName else {
            return nil
        }

        return position(for: ARSkeleton.JointName(rawValue: fallbackRawName), in: frame)
    }

    private func position(for jointName: ARSkeleton.JointName, in frame: MotionFrame) -> SIMD3<Float>? {
        let index = skeletonDefinition.index(for: jointName)
        guard index != NSNotFound, frame.jointPositions.indices.contains(index) else {
            return nil
        }

        let position = frame.jointPositions[index]
        guard position.x.isFinite, position.y.isFinite, position.z.isFinite, position.y > -5 else {
            return nil
        }

        return position
    }

    private func rotation(for jointName: ARSkeleton.JointName, in frame: MotionFrame) -> MotionJointRotation? {
        guard let jointRotations = frame.jointRotations else {
            return nil
        }

        let index = skeletonDefinition.index(for: jointName)
        guard index != NSNotFound, jointRotations.indices.contains(index) else {
            return nil
        }

        return jointRotations[index]
    }

    // MARK: - Character model rendering

    /// Positions the character at floor level (y = 0) tracking the hip's x/z,
    /// without posing individual joints. Used when rotation data is unavailable
    /// (simulator / front-camera captures).
    /// y is fixed at 0 because humanoid USDZ models typically have their pivot at foot level.
    private func renderCharacterAtRoot(frame: MotionFrame) {
        guard let character = characterEntity else { return }
        // In Simulator, ARSkeletonDefinition indices are unavailable (all NSNotFound)
        // and MockMotionSource initializes unset joints to y=-10. Guard against that.
        let hipIndex = skeletonDefinition.index(for: .root)
        let hip: SIMD3<Float>?
        if hipIndex != NSNotFound,
           frame.jointPositions.indices.contains(hipIndex),
           Self.isValidMotionPosition(frame.jointPositions[hipIndex]) {
            hip = frame.jointPositions[hipIndex]
        } else if let first = frame.jointPositions.first(where: Self.isValidMotionPosition) {
            hip = first
        } else {
            hip = nil  // No valid position — leave character at its current position.
        }
        if let hip {
            let floorOffset = activeRigProfile?.floorOffset ?? 0
            character.setPosition(SIMD3<Float>(hip.x, floorOffset, hip.z), relativeTo: nil)
        }
    }

    /// Applies pre-computed joint transforms for the given rig frame index.
    private func renderCharacter(rigFrameIndex: Int) -> Bool {
        guard
            let precomputedRigFrames,
            precomputedRigFrames.indices.contains(rigFrameIndex),
            let modelEntity = skeletalModelEntity
        else { return false }

        if !hasStoppedBuiltInAnimation {
            characterEntity?.stopAllAnimations()
            hasStoppedBuiltInAnimation = true
        }

        modelEntity.jointTransforms = precomputedRigFrames[rigFrameIndex]
        return true
    }

    /// Moves the character entity using the procedural hip position.
    /// Used in Simulator where MockMotionSource produces no valid ARKit joint positions.
    /// The character stays in its USD bind pose but translates with the animation rhythm,
    /// giving visible movement without requiring rotation data or USD skeleton driving.
    private func renderCharacterFallback(frame: MotionFrame) {
        guard let character = characterEntity else { return }
        let fallback = fallbackJointPositions(for: frame)
        let hip = fallback[0]
        // hip.y oscillates around 0.95; offset it relative to that baseline so the
        // character stays near floor level while the subtle bounce comes through.
        let yOffset = hip.y - 0.95
        let floorOffset = activeRigProfile?.floorOffset ?? 0
        character.setPosition(
            SIMD3<Float>(hip.x, floorOffset + yOffset, hip.z),
            relativeTo: nil
        )
    }

    private func fallbackJointPositions(for frame: MotionFrame) -> [SIMD3<Float>] {
        Self.fallbackJointPositions(for: skeletonDebugLayout, time: frame.time)
    }

    nonisolated static func fallbackJointPositions(
        for layout: SkeletonDebugLayout,
        time: TimeInterval
    ) -> [SIMD3<Float>] {
        let pose = proceduralFallbackPose(time: time)

        switch layout {
        case .rawARKit:
            return [
                pose.root,
                pose.head,
                pose.leftShoulder,
                pose.rightShoulder,
                pose.leftUpperArm,
                pose.rightUpperArm,
                pose.leftElbow,
                pose.rightElbow,
                pose.leftWrist,
                pose.rightWrist,
                pose.leftHip,
                pose.rightHip,
                pose.leftKnee,
                pose.rightKnee,
                pose.leftFoot,
                pose.rightFoot,
            ]
        case .canonical:
            return [
                pose.root,
                pose.spine,
                pose.chest,
                pose.neck,
                pose.head,
                pose.leftShoulder,
                pose.rightShoulder,
                pose.leftUpperArm,
                pose.rightUpperArm,
                pose.leftElbow,
                pose.rightElbow,
                pose.leftWrist,
                pose.rightWrist,
                pose.leftHip,
                pose.rightHip,
                pose.leftKnee,
                pose.rightKnee,
                pose.leftAnkle,
                pose.rightAnkle,
                pose.leftFoot,
                pose.rightFoot,
            ]
        case .canonicalTorso:
            return [
                pose.root,
                pose.spine,
                pose.chest,
                pose.neck,
                pose.head,
            ]
        }
    }

    nonisolated private static func proceduralFallbackPose(time: TimeInterval) -> ProceduralFallbackPose {
        let rhythm = Float(time)
        let step = sin(rhythm * 2.2)
        let sway = sin(rhythm * 1.4)
        let armSwing = sin(rhythm * 3.1)
        let bounce = max(0, sin(rhythm * 4.4)) * 0.08

        let root = SIMD3<Float>(sway * 0.18, 0.95 + bounce, step * 0.08)
        let spine = root + SIMD3<Float>(0, 0.18, 0)
        let chest = root + SIMD3<Float>(0, 0.34, 0)
        let neck = root + SIMD3<Float>(0, 0.50, 0)
        let head = root + SIMD3<Float>(0, 0.62, 0)
        let leftShoulder = chest + SIMD3<Float>(-0.18, 0.10, 0)
        let rightShoulder = chest + SIMD3<Float>(0.18, 0.10, 0)
        let leftUpperArm = leftShoulder + SIMD3<Float>(-0.14, 0.02 + armSwing * 0.05, 0.02)
        let rightUpperArm = rightShoulder + SIMD3<Float>(0.14, 0.02 - armSwing * 0.05, 0.02)
        let leftElbow = leftShoulder + SIMD3<Float>(-0.22, 0.04 + armSwing * 0.10, 0.03)
        let rightElbow = rightShoulder + SIMD3<Float>(0.22, 0.04 - armSwing * 0.10, 0.03)
        let leftWrist = leftShoulder + SIMD3<Float>(-0.30, 0.04 + armSwing * 0.18, 0.04)
        let rightWrist = rightShoulder + SIMD3<Float>(0.30, 0.04 - armSwing * 0.18, 0.04)
        let leftHip = root + SIMD3<Float>(-0.12, -0.02, 0)
        let rightHip = root + SIMD3<Float>(0.12, -0.02, 0)
        let leftKnee = leftHip + SIMD3<Float>(-0.03, -0.38 + max(0, step) * 0.08, 0.06)
        let rightKnee = rightHip + SIMD3<Float>(0.03, -0.38 + max(0, -step) * 0.08, -0.06)
        let leftAnkle = leftKnee + SIMD3<Float>(0, -0.38, 0.03 + max(0, step) * 0.04)
        let rightAnkle = rightKnee + SIMD3<Float>(0, -0.38, 0.03 + max(0, -step) * 0.04)
        let leftFoot = leftAnkle + SIMD3<Float>(0, 0, 0.05 + max(0, step) * 0.06)
        let rightFoot = rightAnkle + SIMD3<Float>(0, 0, 0.05 + max(0, -step) * 0.06)

        return ProceduralFallbackPose(
            root: root,
            spine: spine,
            chest: chest,
            neck: neck,
            head: head,
            leftShoulder: leftShoulder,
            rightShoulder: rightShoulder,
            leftUpperArm: leftUpperArm,
            rightUpperArm: rightUpperArm,
            leftElbow: leftElbow,
            rightElbow: rightElbow,
            leftWrist: leftWrist,
            rightWrist: rightWrist,
            leftHip: leftHip,
            rightHip: rightHip,
            leftKnee: leftKnee,
            rightKnee: rightKnee,
            leftAnkle: leftAnkle,
            rightAnkle: rightAnkle,
            leftFoot: leftFoot,
            rightFoot: rightFoot
        )
    }

    private struct ProceduralFallbackPose {
        let root: SIMD3<Float>
        let spine: SIMD3<Float>
        let chest: SIMD3<Float>
        let neck: SIMD3<Float>
        let head: SIMD3<Float>
        let leftShoulder: SIMD3<Float>
        let rightShoulder: SIMD3<Float>
        let leftUpperArm: SIMD3<Float>
        let rightUpperArm: SIMD3<Float>
        let leftElbow: SIMD3<Float>
        let rightElbow: SIMD3<Float>
        let leftWrist: SIMD3<Float>
        let rightWrist: SIMD3<Float>
        let leftHip: SIMD3<Float>
        let rightHip: SIMD3<Float>
        let leftKnee: SIMD3<Float>
        let rightKnee: SIMD3<Float>
        let leftAnkle: SIMD3<Float>
        let rightAnkle: SIMD3<Float>
        let leftFoot: SIMD3<Float>
        let rightFoot: SIMD3<Float>
    }

    nonisolated static func hasUsableJointRotations(_ rotations: [MotionJointRotation?]?) -> Bool {
        rotations?.contains(where: { $0 != nil }) ?? false
    }

    nonisolated private static func isValidMotionPosition(_ position: SIMD3<Float>) -> Bool {
        position.x.isFinite && position.y.isFinite && position.z.isFinite && position.y > -5
    }
}
