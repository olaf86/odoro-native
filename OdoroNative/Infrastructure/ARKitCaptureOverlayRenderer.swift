//
//  ARKitCaptureOverlayRenderer.swift
//  Odoro
//

import ARKit
import Foundation
import RealityKit
import simd

@MainActor
final class ARKitCaptureOverlayRenderer {
    enum DetailLevel: Equatable {
        case preview
        case recording
    }

    private struct RenderJoint {
        let jointName: ARSkeleton.JointName
        let fallbackRawName: String?
    }

    private struct RenderLimb {
        let startIndex: Int
        let endIndex: Int
    }

    private let skeletonDefinition = ARSkeletonDefinition.defaultBody3D
    private let recordingRenderJoints: [RenderJoint] = [
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
    private let previewRenderJoints: [RenderJoint] = [
        .init(jointName: .root, fallbackRawName: "hips_joint"),
        .init(jointName: .head, fallbackRawName: "head_joint"),
        .init(jointName: .leftShoulder, fallbackRawName: "left_shoulder_1_joint"),
        .init(jointName: .rightShoulder, fallbackRawName: "right_shoulder_1_joint"),
        .init(jointName: ARSkeleton.JointName(rawValue: "left_forearm_joint"), fallbackRawName: nil),
        .init(jointName: ARSkeleton.JointName(rawValue: "right_forearm_joint"), fallbackRawName: nil),
        .init(jointName: .leftHand, fallbackRawName: "left_hand_joint"),
        .init(jointName: .rightHand, fallbackRawName: "right_hand_joint"),
        .init(jointName: .leftFoot, fallbackRawName: "left_foot_joint"),
        .init(jointName: .rightFoot, fallbackRawName: "right_foot_joint"),
    ]
    private let recordingRenderLimbs: [RenderLimb] = [
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
    private let previewRenderLimbs: [RenderLimb] = [
        .init(startIndex: 0, endIndex: 1),
        .init(startIndex: 0, endIndex: 2),
        .init(startIndex: 0, endIndex: 3),
        .init(startIndex: 2, endIndex: 4),
        .init(startIndex: 4, endIndex: 6),
        .init(startIndex: 3, endIndex: 5),
        .init(startIndex: 5, endIndex: 7),
        .init(startIndex: 0, endIndex: 8),
        .init(startIndex: 0, endIndex: 9),
    ]

    private weak var view: ARView?
    private var overlayAnchor = AnchorEntity(world: .zero)
    private var jointEntities: [ModelEntity] = []
    private var limbEntities: [ModelEntity] = []
    private var detailLevel: DetailLevel = .preview

    private var renderJoints: [RenderJoint] {
        switch detailLevel {
        case .preview:
            previewRenderJoints
        case .recording:
            recordingRenderJoints
        }
    }

    private var renderLimbs: [RenderLimb] {
        switch detailLevel {
        case .preview:
            previewRenderLimbs
        case .recording:
            recordingRenderLimbs
        }
    }

    func attach(to view: ARView) {
        if self.view !== view {
            overlayAnchor.removeFromParent()
            self.view = view
            configureOverlay(in: view)
        } else if overlayAnchor.scene == nil {
            view.scene.addAnchor(overlayAnchor)
        }
    }

    func setDetailLevel(_ detailLevel: DetailLevel) {
        guard self.detailLevel != detailLevel else {
            return
        }

        self.detailLevel = detailLevel

        if let view {
            overlayAnchor.removeFromParent()
            configureOverlay(in: view)
        }
    }

    func clear() {
        for jointEntity in jointEntities {
            jointEntity.isEnabled = false
        }

        for limbEntity in limbEntities {
            limbEntity.isEnabled = false
        }
    }

    func render(frame: MotionFrame) {
        guard !jointEntities.isEmpty, limbEntities.count == renderLimbs.count else {
            return
        }

        let jointPositions = renderJoints.map { position(for: $0, in: frame) }

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

            limbEntity.position = (start + end) * 0.5
            limbEntity.orientation = simd_quatf(from: SIMD3<Float>(0, 1, 0), to: simd_normalize(delta))
            limbEntity.scale = [1, length, 1]
            limbEntity.isEnabled = true
        }
    }

    private func configureOverlay(in view: ARView) {
        overlayAnchor = AnchorEntity(world: .zero)
        jointEntities.removeAll()
        limbEntities.removeAll()

        let jointMaterial = UnlitMaterial(color: UIColor(red: 1.0, green: 0.37, blue: 0.47, alpha: 0.92))
        let limbMaterial = UnlitMaterial(color: UIColor(red: 0.29, green: 0.92, blue: 0.84, alpha: 0.88))

        for _ in renderJoints {
            let jointEntity = ModelEntity(
                mesh: .generateSphere(radius: 0.018),
                materials: [jointMaterial]
            )
            jointEntity.isEnabled = false
            jointEntities.append(jointEntity)
            overlayAnchor.addChild(jointEntity)
        }

        for _ in renderLimbs {
            let limbMesh: MeshResource
            if #available(iOS 18.0, *) {
                limbMesh = .generateCylinder(height: 1.0, radius: 0.008)
            } else {
                limbMesh = .generateBox(size: [0.016, 1.0, 0.016])
            }

            let limbEntity = ModelEntity(mesh: limbMesh, materials: [limbMaterial])
            limbEntity.isEnabled = false
            limbEntities.append(limbEntity)
            overlayAnchor.addChild(limbEntity)
        }

        view.scene.addAnchor(overlayAnchor)
    }

    private func position(for renderJoint: RenderJoint, in frame: MotionFrame) -> SIMD3<Float>? {
        if let position = position(for: renderJoint.jointName, in: frame) {
            return position
        }

        guard let fallbackRawName = renderJoint.fallbackRawName else {
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
}
