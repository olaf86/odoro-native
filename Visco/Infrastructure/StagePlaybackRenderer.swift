//
//  StagePlaybackRenderer.swift
//  Visco
//

import ARKit
import Foundation
import RealityKit
import UIKit

@MainActor
final class StagePlaybackRenderer: NSObject {
    private let skeletonDefinition = ARSkeletonDefinition.defaultBody3D
    private lazy var limbPairs: [(Int, Int)] = {
        skeletonDefinition.parentIndices.enumerated().compactMap { childIndex, parentIndex in
            guard parentIndex >= 0 else {
                return nil
            }
            return (parentIndex, childIndex)
        }
    }()

    private weak var view: ARView?
    private var clip: MotionClip?
    private var playbackTimer: Timer?
    private var playbackStartedAt: Date?

    private var stageAnchor = AnchorEntity()
    private var dancerRoot = Entity()
    private var jointEntities: [ModelEntity] = []
    private var limbEntities: [ModelEntity] = []

    func attach(to view: ARView) {
        self.view = view
        configureScene(in: view)
        if let clip, let firstFrame = clip.frames.first {
            render(frame: firstFrame)
        }
    }

    func setClip(_ clip: MotionClip?) {
        self.clip = clip

        if let firstFrame = clip?.frames.first {
            render(frame: firstFrame)
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
        for _ in 0..<skeletonDefinition.jointNames.count {
            let joint = ModelEntity(
                mesh: .generateSphere(radius: 0.035),
                materials: [UnlitMaterial(color: UIColor(red: 1, green: 0.33, blue: 0.48, alpha: 1))]
            )
            jointEntities.append(joint)
            dancerRoot.addChild(joint)
        }

        for _ in limbPairs {
            let limb = ModelEntity(
                mesh: .generateBox(size: [0.018, 1.0, 0.018]),
                materials: [UnlitMaterial(color: UIColor(red: 0.38, green: 0.89, blue: 0.86, alpha: 1))]
            )
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
        guard frame.jointPositions.count == jointEntities.count else {
            return
        }

        for (index, jointEntity) in jointEntities.enumerated() {
            let position = frame.jointPositions[index]
            jointEntity.position = position
            jointEntity.isEnabled = position.x.isFinite && position.y.isFinite && position.z.isFinite && position.y > -5
        }

        for (index, pair) in limbPairs.enumerated() {
            let parent = frame.jointPositions[pair.0]
            let child = frame.jointPositions[pair.1]
            let delta = child - parent
            let length = simd_length(delta)
            let limb = limbEntities[index]

            guard length > 0.0001, parent.y > -5, child.y > -5 else {
                limb.isEnabled = false
                continue
            }

            limb.isEnabled = true
            limb.position = (parent + child) * 0.5
            limb.orientation = simd_quatf(from: SIMD3<Float>(0, 1, 0), to: simd_normalize(delta))
            limb.scale = [1, length, 1]
        }
    }
}
