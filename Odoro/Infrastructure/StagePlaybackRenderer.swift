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
    private struct RenderLimb {
        let startIndex: Int
        let endIndex: Int
    }

    private let skeletonDefinition = ARSkeletonDefinition.defaultBody3D
    private let renderJointNames: [OdoroJointName] = [
        .root,
        .head,
        .leftShoulder,
        .rightShoulder,
        .leftWrist,
        .rightWrist,
        .leftHip,
        .rightHip,
        .leftKnee,
        .rightKnee,
        .leftFoot,
        .rightFoot,
    ]
    private let renderLimbs: [RenderLimb] = [
        .init(startIndex: 0, endIndex: 1),
        .init(startIndex: 2, endIndex: 3),
        .init(startIndex: 0, endIndex: 2),
        .init(startIndex: 0, endIndex: 3),
        .init(startIndex: 2, endIndex: 4),
        .init(startIndex: 3, endIndex: 5),
        .init(startIndex: 0, endIndex: 6),
        .init(startIndex: 0, endIndex: 7),
        .init(startIndex: 6, endIndex: 8),
        .init(startIndex: 7, endIndex: 9),
        .init(startIndex: 8, endIndex: 10),
        .init(startIndex: 9, endIndex: 11),
    ]

    private weak var view: ARView?
    private var clip: MotionClip?
    private var playbackTimer: Timer?
    private var playbackStartedAt: Date?
    private var usesProceduralMockPlayback = false

    private var stageAnchor = AnchorEntity()
    private var dancerRoot = Entity()
    private var jointEntities: [ModelEntity] = []
    private var limbEntities: [ModelEntity] = []

    private var characterEntity: Entity?
    private var skeletalModelEntity: ModelEntity?
    // USD skeleton joint order → ARKit joint index (NSNotFound if unmapped)
    private var usdJointArkitIndices: [Int] = []
    // USD skeleton joint order → parent ARKit joint index (nil = treat as world-space root)
    private var usdJointParentArkitIndices: [Int?] = []

    // Joint order and parent names extracted from robot.usdz skel:joints array.
    // Leaf names match ARKit joint names exactly; parents not in this list (spine_3, spine_7,
    // neck_1) exist in the full ARKit skeleton so their indices are still resolvable.
    private static let robotUsdJoints: [(joint: String, parent: String?)] = [
        ("spine_2_joint",         "spine_1_joint"),
        ("spine_5_joint",         "spine_4_joint"),
        ("hips_joint",            nil),
        ("spine_6_joint",         "spine_5_joint"),
        ("head_joint",            "neck_4_joint"),
        ("spine_1_joint",         "hips_joint"),
        ("spine_4_joint",         "spine_3_joint"),
        ("neck_2_joint",          "neck_1_joint"),
        ("left_leg_joint",        "left_upLeg_joint"),
        ("left_foot_joint",       "left_leg_joint"),
        ("left_arm_joint",        "left_shoulder_1_joint"),
        ("left_forearm_joint",    "left_arm_joint"),
        ("left_upLeg_joint",      "hips_joint"),
        ("left_hand_joint",       "left_forearm_joint"),
        ("left_shoulder_1_joint", "spine_7_joint"),
        ("neck_3_joint",          "neck_2_joint"),
        ("neck_4_joint",          "neck_3_joint"),
        ("right_leg_joint",       "right_upLeg_joint"),
        ("right_foot_joint",      "right_leg_joint"),
        ("right_arm_joint",       "right_shoulder_1_joint"),
        ("right_forearm_joint",   "right_arm_joint"),
        ("right_upLeg_joint",     "hips_joint"),
        ("right_hand_joint",      "right_forearm_joint"),
        ("right_shoulder_1_joint","spine_7_joint"),
    ]

    override init() {
        super.init()
        loadCharacterIfAvailable()
    }

    func attach(to view: ARView) {
        self.view = view
        configureScene(in: view)
        if let clip, let firstFrame = clip.frames.first {
            render(frame: firstFrame)
        }
    }

    func setClip(_ clip: MotionClip?) {
        self.clip = clip

        if let firstFrame = clip?.frames.first, !jointEntities.isEmpty, !limbEntities.isEmpty {
            render(frame: firstFrame)
        }
    }

    func setUsesProceduralMockPlayback(_ usesProceduralMockPlayback: Bool) {
        self.usesProceduralMockPlayback = usesProceduralMockPlayback
    }

    // MARK: - Character model loading

    private func loadCharacterIfAvailable() {
        do {
            let entity = try Entity.load(named: "robot")
            characterEntity = entity
            skeletalModelEntity = findModelEntity(entity)
            setupSkeletalMapping()
            let mappedCount = self.usdJointArkitIndices.filter { $0 != NSNotFound }.count
            Self.logger.info("robot.usdz loaded — skeletal model: \(self.skeletalModelEntity != nil), mapped: \(mappedCount)/\(Self.robotUsdJoints.count)")
        } catch {
            Self.logger.error("Failed to load robot.usdz: \(error)")
        }
    }

    private func findModelEntity(_ entity: Entity) -> ModelEntity? {
        if let me = entity as? ModelEntity { return me }
        for child in entity.children {
            if let found = findModelEntity(child) { return found }
        }
        return nil
    }

    private func setupSkeletalMapping() {
        usdJointArkitIndices = Self.robotUsdJoints.map { entry in
            skeletonDefinition.index(for: ARSkeleton.JointName(rawValue: entry.joint))
        }
        usdJointParentArkitIndices = Self.robotUsdJoints.map { entry in
            guard let parentName = entry.parent else { return nil }
            let idx = skeletonDefinition.index(for: ARSkeleton.JointName(rawValue: parentName))
            return idx == NSNotFound ? nil : idx
        }
    }

    func play() {
        guard let clip, !clip.isEmpty else { return }

        pause()
        render(frame: clip.frames[0])
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

        view.backgroundColor = UIColor(red: 0.03, green: 0.03, blue: 0.06, alpha: 1)
        view.scene.anchors.removeAll()

        stageAnchor = AnchorEntity()
        dancerRoot = Entity()
        jointEntities.removeAll()
        limbEntities.removeAll()

        let floor = ModelEntity(
            mesh: .generateBox(size: [2.8, 0.06, 2.8]),
            materials: [UnlitMaterial(color: UIColor(red: 0.11, green: 0.14, blue: 0.22, alpha: 1))]
        )
        floor.position = [0, -0.03, 0]
        stageAnchor.addChild(floor)

        let backdrop = ModelEntity(
            mesh: .generateBox(size: [3.2, 1.8, 0.05]),
            materials: [UnlitMaterial(color: UIColor(red: 0.08, green: 0.08, blue: 0.14, alpha: 1))]
        )
        backdrop.position = [0, 0.9, -1.1]
        stageAnchor.addChild(backdrop)

        let spotlight = ModelEntity(
            mesh: .generateSphere(radius: 0.18),
            materials: [UnlitMaterial(color: UIColor(red: 0.99, green: 0.74, blue: 0.28, alpha: 1))]
        )
        spotlight.position = [0, 1.55, -0.75]
        stageAnchor.addChild(spotlight)

        buildDancerHierarchy()
        stageAnchor.addChild(dancerRoot)

        let camera = Entity()
        camera.components.set(PerspectiveCameraComponent())
        camera.look(at: [0, 0.95, 0], from: [0, 1.35, 3.4], relativeTo: nil)
        stageAnchor.addChild(camera)

        view.scene.addAnchor(stageAnchor)
    }

    private func buildDancerHierarchy() {
        // Character model takes priority over the procedural skeleton
        // whenever the entity loaded, even if individual joints are not yet mapped.
        let hasCharacter = characterEntity != nil

        if let character = characterEntity {
            character.removeFromParent()
            character.position = .zero  // Ensure character starts at floor level.
            dancerRoot.addChild(character)
        }

        for _ in renderJointNames {
            let joint = ModelEntity(
                mesh: .generateSphere(radius: 0.045),
                materials: [UnlitMaterial(color: UIColor(red: 1, green: 0.33, blue: 0.48, alpha: 1))]
            )
            joint.isEnabled = !hasCharacter
            jointEntities.append(joint)
            dancerRoot.addChild(joint)
        }

        for _ in renderLimbs {
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
        let frame = clip.frames.last { $0.time <= elapsed } ?? clip.frames[0]
        render(frame: frame)
    }

    private func render(frame: MotionFrame) {
        if characterEntity != nil {
            if !usdJointArkitIndices.isEmpty, let rotations = frame.jointRotations, !rotations.isEmpty {
                // ARKit capture: drive skeleton via SkeletalPosesComponent.
                renderCharacter(frame: frame, rotations: rotations)
            } else {
                // Simulator / front-camera: no rotation data — bind pose at floor level.
                renderCharacterAtRoot(frame: frame)
            }
            return
        }

        var jointPositions = resolvedJointPositions(from: frame)
        guard jointEntities.count == jointPositions.count, limbEntities.count == renderLimbs.count else {
            return
        }

        if shouldUseProceduralFallback(for: jointPositions) {
            jointPositions = fallbackJointPositions(for: frame).map(Optional.some)
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
    }

    private func resolvedJointPositions(from frame: MotionFrame) -> [SIMD3<Float>?] {
        if frame.jointPositions.count == OdoroSkeletonDefinition.jointCount {
            return renderJointNames.map { jointName in
                canonicalPosition(for: jointName, in: frame)
            }
        }

        return [
            resolvedPosition(for: .root, fallbackRawName: "hips_joint", in: frame),
            resolvedPosition(for: .head, fallbackRawName: "head_joint", in: frame),
            resolvedPosition(for: .leftShoulder, fallbackRawName: "left_shoulder_1_joint", in: frame),
            resolvedPosition(for: .rightShoulder, fallbackRawName: "right_shoulder_1_joint", in: frame),
            resolvedPosition(for: .leftHand, fallbackRawName: "left_hand_joint", in: frame),
            resolvedPosition(for: .rightHand, fallbackRawName: "right_hand_joint", in: frame),
            resolvedPosition(for: ARSkeleton.JointName(rawValue: "left_upLeg_joint"), in: frame),
            resolvedPosition(for: ARSkeleton.JointName(rawValue: "right_upLeg_joint"), in: frame),
            resolvedPosition(for: ARSkeleton.JointName(rawValue: "left_leg_joint"), in: frame),
            resolvedPosition(for: ARSkeleton.JointName(rawValue: "right_leg_joint"), in: frame),
            resolvedPosition(for: .leftFoot, fallbackRawName: "left_foot_joint", in: frame),
            resolvedPosition(for: .rightFoot, fallbackRawName: "right_foot_joint", in: frame),
        ]
    }

    private func canonicalPosition(for jointName: OdoroJointName, in frame: MotionFrame) -> SIMD3<Float>? {
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
        let validPosition: ((SIMD3<Float>) -> Bool) = { $0.y > -5 }
        let hip: SIMD3<Float>?
        if hipIndex != NSNotFound,
           frame.jointPositions.indices.contains(hipIndex),
           validPosition(frame.jointPositions[hipIndex]) {
            hip = frame.jointPositions[hipIndex]
        } else if let first = frame.jointPositions.first(where: validPosition) {
            hip = first
        } else {
            hip = nil  // No valid position — leave character at its current position.
        }
        if let hip {
            character.setPosition(SIMD3<Float>(hip.x, 0, hip.z), relativeTo: nil)
        }
    }

    /// Drives the skeleton via SkeletalPosesComponent.
    ///
    /// robot.usdz uses USD Skeleton schema — joints are not exposed as entity children.
    /// We convert world-space ARKit rotations/positions to local-space transforms
    /// (each joint relative to its parent) and push them via SkeletalPosesComponent.
    private func renderCharacter(frame: MotionFrame, rotations: [MotionJointRotation?]) {
        guard let modelEntity = skeletalModelEntity,
              frame.jointPositions.count == rotations.count else { return }

        var joints: [(String, Transform)] = []
        joints.reserveCapacity(Self.robotUsdJoints.count)

        for usdIdx in 0..<Self.robotUsdJoints.count {
            let jointName = Self.robotUsdJoints[usdIdx].joint
            let arkitIdx = usdJointArkitIndices[usdIdx]
            guard arkitIdx != NSNotFound,
                  frame.jointPositions.indices.contains(arkitIdx),
                  let worldRot = rotations[arkitIdx]?.simdValue else { continue }

            let worldPos = frame.jointPositions[arkitIdx]
            let localTransform: Transform

            if let parentArkitIdx = usdJointParentArkitIndices[usdIdx],
               frame.jointPositions.indices.contains(parentArkitIdx),
               let parentWorldRot = rotations[parentArkitIdx]?.simdValue {
                // Convert world-space to parent-relative local-space.
                let parentPos = frame.jointPositions[parentArkitIdx]
                let parentRotInv = parentWorldRot.inverse
                localTransform = Transform(
                    rotation: parentRotInv * worldRot,
                    translation: simd_act(parentRotInv, worldPos - parentPos)
                )
            } else {
                // Root joint or parent not in ARKit frame — world space is local space.
                localTransform = Transform(rotation: worldRot, translation: worldPos)
            }

            joints.append((jointName, localTransform))
        }

        if #available(iOS 18.0, *) {
            let pose = SkeletalPose(id: "live", joints: joints)
            var posesComp = modelEntity.components[SkeletalPosesComponent.self] ?? SkeletalPosesComponent(poses: [])
            posesComp.poses.set(pose)
            modelEntity.components[SkeletalPosesComponent.self] = posesComp
        }
    }

    private func fallbackJointPositions(for frame: MotionFrame) -> [SIMD3<Float>] {
        let rhythm = Float(frame.time)
        let step = sin(rhythm * 2.2)
        let sway = sin(rhythm * 1.4)
        let armSwing = sin(rhythm * 3.1)
        let bounce = max(0, sin(rhythm * 4.4)) * 0.08

        let root = SIMD3<Float>(sway * 0.18, 0.95 + bounce, step * 0.08)
        let head = root + SIMD3<Float>(0, 0.62, 0)
        let leftShoulder = root + SIMD3<Float>(-0.18, 0.44, 0)
        let rightShoulder = root + SIMD3<Float>(0.18, 0.44, 0)
        let leftHand = leftShoulder + SIMD3<Float>(-0.30, 0.04 + armSwing * 0.18, 0.04)
        let rightHand = rightShoulder + SIMD3<Float>(0.30, 0.04 - armSwing * 0.18, 0.04)
        let leftUpLeg = root + SIMD3<Float>(-0.12, -0.02, 0)
        let rightUpLeg = root + SIMD3<Float>(0.12, -0.02, 0)
        let leftLeg = leftUpLeg + SIMD3<Float>(-0.03, -0.38 + max(0, step) * 0.08, 0.06)
        let rightLeg = rightUpLeg + SIMD3<Float>(0.03, -0.38 + max(0, -step) * 0.08, -0.06)
        let leftFoot = leftLeg + SIMD3<Float>(0, -0.38, 0.05 + max(0, step) * 0.10)
        let rightFoot = rightLeg + SIMD3<Float>(0, -0.38, 0.05 + max(0, -step) * 0.10)

        return [
            root,
            head,
            leftShoulder,
            rightShoulder,
            leftHand,
            rightHand,
            leftUpLeg,
            rightUpLeg,
            leftLeg,
            rightLeg,
            leftFoot,
            rightFoot,
        ]
    }
}
