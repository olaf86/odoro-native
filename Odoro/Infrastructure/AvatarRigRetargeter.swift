//
//  AvatarRigRetargeter.swift
//  Odoro

import RealityKit
import simd

/// Maps an AvatarDrivePose onto a model's joint transforms using an AvatarRigProfile.
///
/// The key invariant: rotation is computed as a delta from T-pose in the parent space
/// defined by the rig profile's parentSourceJoint.  Both the motion sample and the
/// T-pose neutral rotation are expressed relative to that same parent, so the reference
/// frame is consistent regardless of the capture backend's skeleton hierarchy.
///
///     motionLocalRot   = parentWorldRot.inverse × jointWorldRot
///     tPoseLocalRot    = tPoseParentWorldRot.inverse × tPoseJointWorldRot
///     delta            = tPoseLocalRot.inverse × motionLocalRot
///     modelLocalRot    = bindPoseLocalRot × weighted(delta)
///
/// This eliminates the ARKit-hierarchy dependency that caused reference-frame
/// mismatches for VRoid models, while producing identical results for the robot
/// (whose rig profile already mirrors ARKit's parent-child structure).
struct AvatarRigRetargeter {
    private enum DirectionalBoneSpec {
        case leftUpperArm
        case rightUpperArm
        case leftForearm
        case rightForearm

        nonisolated init?(joint: OdoroJointName?) {
            switch joint {
            case .leftUpperArm:
                self = .leftUpperArm
            case .rightUpperArm:
                self = .rightUpperArm
            case .leftElbow:
                self = .leftForearm
            case .rightElbow:
                self = .rightForearm
            default:
                return nil
            }
        }

        nonisolated var startJoint: OdoroJointName {
            switch self {
            case .leftUpperArm:
                .leftShoulder
            case .rightUpperArm:
                .rightShoulder
            case .leftForearm:
                .leftElbow
            case .rightForearm:
                .rightElbow
            }
        }

        nonisolated var endJoint: OdoroJointName {
            switch self {
            case .leftUpperArm:
                .leftElbow
            case .rightUpperArm:
                .rightElbow
            case .leftForearm:
                .leftWrist
            case .rightForearm:
                .rightWrist
            }
        }

        nonisolated var childJoint: OdoroJointName {
            switch self {
            case .leftUpperArm:
                .leftElbow
            case .rightUpperArm:
                .rightElbow
            case .leftForearm:
                .leftWrist
            case .rightForearm:
                .rightWrist
            }
        }

        nonisolated var maximumTwistRadians: Float {
            switch self {
            case .leftUpperArm, .rightUpperArm:
                1.35
            case .leftForearm, .rightForearm:
                1.20
            }
        }

        nonisolated var twistWeight: Float {
            switch self {
            case .leftUpperArm, .rightUpperArm:
                1.00
            case .leftForearm, .rightForearm:
                0.35
            }
        }

        nonisolated var usesTorsoReferenceTwist: Bool {
            switch self {
            case .leftUpperArm, .rightUpperArm:
                true
            case .leftForearm, .rightForearm:
                false
            }
        }

        nonisolated var oppositeShoulder: OdoroJointName {
            switch self {
            case .leftUpperArm, .leftForearm:
                .rightShoulder
            case .rightUpperArm, .rightForearm:
                .leftShoulder
            }
        }
    }

    private enum Tuning {
        nonisolated static let smallRotationDelta: Float     = 0.08
        nonisolated static let largeRotationDelta: Float     = 0.75
        nonisolated static let minimumRotationAlpha: Float   = 0.08
        nonisolated static let maximumRotationAlpha: Float   = 0.88
        nonisolated static let headMaximumRotationAlpha: Float = 0.65

        nonisolated static let smallTranslationDelta: Float  = 0.08
        nonisolated static let largeTranslationDelta: Float  = 0.16
        nonisolated static let minimumTranslationAlpha: Float = 0.08
        nonisolated static let maximumTranslationAlpha: Float = 0.78
    }

    let profile: AvatarRigProfile
    let bindPoseTransforms: [Transform]
    let modelJointIndices: [String: Int]
    let tPose: AvatarDrivePose

    // MARK: - Per-frame retargeting

    /// Retargets a single pose onto the model's joint transforms.
    ///
    /// - Parameters:
    ///   - pose: Canonical world-space pose for this frame.
    ///   - previousTransforms: The joint transforms from the previous frame, used for
    ///     continuity smoothing. Pass nil for the first frame.
    /// - Returns: A full `[Transform]` array covering all model joints (unbound joints
    ///   keep their bind-pose transform).
    func retargetFrame(_ pose: AvatarDrivePose, previousTransforms: [Transform]?) -> [Transform] {
        var transforms = bindPoseTransforms
        var resolvedCount = 0

        for binding in profile.bindings {
            guard
                let targetIndex = modelJointIndices[binding.boneName],
                transforms.indices.contains(targetIndex),
                let worldPos = pose.worldPosition(for: binding.sourceJoint),
                let worldRot = pose.worldRotation(for: binding.sourceJoint),
                let tPoseWorldRot = tPose.worldRotation(for: binding.sourceJoint)
            else { continue }

            let parentWorldRot = pose.worldRotation(for: binding.parentSourceJoint)
            let parentWorldPos = pose.worldPosition(for: binding.parentSourceJoint)
            let tPoseParentWorldRot = tPose.worldRotation(for: binding.parentSourceJoint)

            let resolvedWorldRot = binding.rotationOffset.map { worldRot * $0.simdValue } ?? worldRot

            var target = Self.retargetedLocalTransform(
                baseTransform: bindPoseTransforms[targetIndex],
                worldRotation: resolvedWorldRot,
                worldPosition: worldPos,
                parentWorldRotation: parentWorldRot,
                parentWorldPosition: parentWorldPos,
                tPoseWorldRotation: tPoseWorldRot,
                tPoseParentWorldRotation: tPoseParentWorldRot,
                translationMode: binding.translationMode,
                rotationWeight: binding.weight,
                floorOffset: profile.floorOffset
            )

            if let directionalRotation = directionRetargetedLocalRotation(
                targetIndex: targetIndex,
                binding: binding,
                pose: pose,
                tPose: tPose
            ) {
                target.rotation = directionalRotation
            }

            let isRootJoint = binding.translationMode == .direct
                && binding.sourceJoint.canonicalJoint == .root
            let isHeadJoint = binding.sourceJoint.canonicalJoint == .head
            let maxRotAlpha = isHeadJoint
                ? Tuning.headMaximumRotationAlpha
                : Tuning.maximumRotationAlpha

            transforms[targetIndex] = Self.stabilizedLocalTransform(
                previous: previousTransforms.flatMap {
                    $0.indices.contains(targetIndex) ? $0[targetIndex] : nil
                },
                target: target,
                smoothsTranslation: isRootJoint,
                maximumRotationAlpha: maxRotAlpha
            )
            resolvedCount += 1
        }

        return resolvedCount > 0 ? transforms : bindPoseTransforms
    }

    // MARK: - Static transform computation

    /// Computes the model-local joint transform for a single binding.
    ///
    /// Rotation: delta from T-pose applied on top of the bind pose, in the rig profile's
    /// parent-joint space (not ARKit's skeleton hierarchy).
    /// Translation: world-space retargeting (`.direct`) or bind-pose preserved (`.bindPose`).
    nonisolated static func retargetedLocalTransform(
        baseTransform: Transform,
        worldRotation: simd_quatf,
        worldPosition: SIMD3<Float>,
        parentWorldRotation: simd_quatf?,
        parentWorldPosition: SIMD3<Float>?,
        tPoseWorldRotation: simd_quatf,
        tPoseParentWorldRotation: simd_quatf?,
        translationMode: AvatarTranslationMode,
        rotationWeight: Float,
        floorOffset: Float
    ) -> Transform {
        var result = baseTransform

        // Express both motion and T-pose in the same parent space so the delta is
        // meaningful regardless of where the joint sits in the capture backend's hierarchy.
        let parentRot = parentWorldRotation ?? .identity
        let tPoseParentRot = tPoseParentWorldRotation ?? .identity

        let motionLocalRot = parentRot.inverse * worldRotation
        let tPoseLocalRot  = tPoseParentRot.inverse * tPoseWorldRotation

        let delta = tPoseLocalRot.inverse * motionLocalRot
        result.rotation = baseTransform.rotation * weightedRotation(delta, weight: rotationWeight)

        switch translationMode {
        case .direct:
            if let parentWorldRot = parentWorldRotation, let parentWorldPos = parentWorldPosition {
                result.translation = simd_act(parentWorldRot.inverse, worldPosition - parentWorldPos)
            } else {
                result.translation = worldPosition - SIMD3<Float>(0, floorOffset, 0)
            }
        case .bindPose:
            break
        }

        return result
    }

    // MARK: - Rotation utilities

    /// Blends a rotation toward identity by `weight` using slerp.
    nonisolated static func weightedRotation(_ rotation: simd_quatf, weight: Float) -> simd_quatf {
        let w = min(max(weight, 0), 1)
        guard w < 0.999 else { return rotation }
        return simd_slerp(.identity, rotation, w)
    }

    private func directionRetargetedLocalRotation(
        targetIndex: Int,
        binding: AvatarBoneBinding,
        pose: AvatarDrivePose,
        tPose: AvatarDrivePose
    ) -> simd_quatf? {
        guard let spec = DirectionalBoneSpec(joint: binding.sourceJoint.canonicalJoint) else {
            return nil
        }
        let baseTransform = bindPoseTransforms[targetIndex]
        guard let targetBindDirectionParent = targetBindDirectionParent(for: spec) else {
            return nil
        }

        guard
            let start = pose.worldPosition(for: spec.startJoint),
            let end = pose.worldPosition(for: spec.endJoint),
            let tPoseStart = tPose.worldPosition(for: spec.startJoint),
            let tPoseEnd = tPose.worldPosition(for: spec.endJoint),
            let currentDirectionWorld = Self.normalizedDirection(from: start, to: end),
            let tPoseDirectionWorld = Self.normalizedDirection(from: tPoseStart, to: tPoseEnd)
        else {
            return nil
        }

        let parentRotation = pose.worldRotation(for: binding.parentSourceJoint) ?? .identity
        let tPoseParentRotation = tPose.worldRotation(for: binding.parentSourceJoint) ?? .identity

        let currentDirectionLocal = simd_act(parentRotation.inverse, currentDirectionWorld)
        let tPoseDirectionLocal = simd_act(tPoseParentRotation.inverse, tPoseDirectionWorld)

        guard
            let normalizedCurrentDirectionLocal = Self.normalized(currentDirectionLocal),
            let normalizedTPoseDirectionLocal = Self.normalized(tPoseDirectionLocal)
        else {
            return nil
        }

        let targetCurrentAimLocal = mappedTargetAimLocal(
            spec: spec,
            binding: binding,
            sourceCurrentAimLocal: normalizedCurrentDirectionLocal,
            sourceTPoseAimLocal: normalizedTPoseDirectionLocal,
            targetBindAimLocal: targetBindDirectionParent,
            pose: pose,
            tPose: tPose,
            parentRotation: parentRotation,
            tPoseParentRotation: tPoseParentRotation
        ) ?? simd_act(
            Self.rotationAligning(
                from: normalizedTPoseDirectionLocal,
                to: normalizedCurrentDirectionLocal
            ),
            targetBindDirectionParent
        )
        let swing = Self.rotationAligning(
            from: targetBindDirectionParent,
            to: targetCurrentAimLocal
        )

        let motionLocalRotation = Self.localRotation(
            worldRotation: pose.worldRotation(for: binding.sourceJoint),
            parentWorldRotation: pose.worldRotation(for: binding.parentSourceJoint)
        )
        let tPoseLocalRotation = Self.localRotation(
            worldRotation: tPose.worldRotation(for: binding.sourceJoint),
            parentWorldRotation: tPose.worldRotation(for: binding.parentSourceJoint)
        )

        let clampedTwist: simd_quatf
        if spec.usesTorsoReferenceTwist,
           let torsoTwist = torsoReferenceTwistRotation(
                spec: spec,
                pose: pose,
                tPose: tPose,
                parentRotation: parentRotation,
                tPoseParentRotation: tPoseParentRotation,
                currentSourceAimLocal: normalizedCurrentDirectionLocal,
                tPoseSourceAimLocal: normalizedTPoseDirectionLocal,
                targetCurrentAimLocal: targetCurrentAimLocal,
                maximumRadians: spec.maximumTwistRadians,
                twistWeight: spec.twistWeight * binding.weight
           ) {
            clampedTwist = torsoTwist
        } else {
            clampedTwist = Self.clampedTwistRotation(
                motionLocalRotation: motionLocalRotation,
                tPoseLocalRotation: tPoseLocalRotation,
                sourceAxis: normalizedTPoseDirectionLocal,
                targetAxis: targetCurrentAimLocal,
                maximumRadians: spec.maximumTwistRadians,
                twistWeight: spec.twistWeight * binding.weight
            )
        }

        let composedRotation = clampedTwist * (swing * baseTransform.rotation)
        return simd_slerp(baseTransform.rotation, composedRotation, binding.weight)
    }

    // MARK: - Continuity stabilization

    /// Smooths a joint transform between frames to suppress large inter-frame jumps.
    ///
    /// Rotation alpha falls as the frame-to-frame angle delta grows, preventing
    /// skeleton teleports from noisy capture data. Translation smoothing is only
    /// applied to the root joint; all others receive the target translation directly.
    nonisolated static func stabilizedLocalTransform(
        previous: Transform?,
        target: Transform,
        smoothsTranslation: Bool = false,
        maximumRotationAlpha: Float = Tuning.maximumRotationAlpha
    ) -> Transform {
        guard let previous else { return target }

        let rotDelta = angleBetween(previous.rotation, target.rotation)
        let rotAlpha = continuityBlendAlpha(
            delta: rotDelta,
            smallDelta: Tuning.smallRotationDelta,
            largeDelta: Tuning.largeRotationDelta,
            minimumAlpha: Tuning.minimumRotationAlpha,
            maximumAlpha: maximumRotationAlpha
        )

        let smoothedTranslation: SIMD3<Float>
        if smoothsTranslation {
            let transDelta = simd_length(target.translation - previous.translation)
            let transAlpha = continuityBlendAlpha(
                delta: transDelta,
                smallDelta: Tuning.smallTranslationDelta,
                largeDelta: Tuning.largeTranslationDelta,
                minimumAlpha: Tuning.minimumTranslationAlpha,
                maximumAlpha: Tuning.maximumTranslationAlpha
            )
            smoothedTranslation = previous.translation + (target.translation - previous.translation) * transAlpha
        } else {
            smoothedTranslation = target.translation
        }

        return Transform(
            scale: target.scale,
            rotation: simd_slerp(previous.rotation, target.rotation, rotAlpha),
            translation: smoothedTranslation
        )
    }

    // MARK: - Private helpers

    nonisolated private static func continuityBlendAlpha(
        delta: Float,
        smallDelta: Float,
        largeDelta: Float,
        minimumAlpha: Float,
        maximumAlpha: Float
    ) -> Float {
        guard largeDelta > smallDelta else { return maximumAlpha }
        if delta <= smallDelta { return maximumAlpha }
        if delta >= largeDelta { return minimumAlpha }
        let progress = (delta - smallDelta) / (largeDelta - smallDelta)
        return maximumAlpha + (minimumAlpha - maximumAlpha) * progress
    }

    nonisolated private static func angleBetween(_ lhs: simd_quatf, _ rhs: simd_quatf) -> Float {
        let dot = abs(simd_dot(lhs.vector, rhs.vector))
        return 2 * acos(min(max(dot, -1), 1))
    }

    nonisolated private static func normalizedDirection(
        from start: SIMD3<Float>,
        to end: SIMD3<Float>
    ) -> SIMD3<Float>? {
        normalized(end - start)
    }

    nonisolated private static func normalized(_ vector: SIMD3<Float>) -> SIMD3<Float>? {
        let length = simd_length(vector)
        guard length > 0.0001 else { return nil }
        return vector / length
    }

    nonisolated private static func localRotation(
        worldRotation: simd_quatf?,
        parentWorldRotation: simd_quatf?
    ) -> simd_quatf? {
        guard let worldRotation else { return nil }
        let parentRotation = parentWorldRotation ?? .identity
        return parentRotation.inverse * worldRotation
    }

    nonisolated private static func rotationAligning(
        from source: SIMD3<Float>,
        to target: SIMD3<Float>
    ) -> simd_quatf {
        let dot = simd_dot(source, target)
        if dot > 0.9999 {
            return .identity
        }
        if dot < -0.9999 {
            return simd_quatf(angle: .pi, axis: orthogonalUnitVector(to: source))
        }

        return simd_quatf(from: source, to: target)
    }

    nonisolated private static func orthogonalUnitVector(to vector: SIMD3<Float>) -> SIMD3<Float> {
        let basis = abs(vector.x) < 0.9 ? SIMD3<Float>(1, 0, 0) : SIMD3<Float>(0, 1, 0)
        return simd_normalize(simd_cross(vector, basis))
    }

    nonisolated private static func clampedTwistRotation(
        motionLocalRotation: simd_quatf?,
        tPoseLocalRotation: simd_quatf?,
        sourceAxis: SIMD3<Float>,
        targetAxis: SIMD3<Float>,
        maximumRadians: Float,
        twistWeight: Float
    ) -> simd_quatf {
        guard
            let motionLocalRotation,
            let tPoseLocalRotation
        else {
            return .identity
        }

        let delta = tPoseLocalRotation.inverse * motionLocalRotation
        let (_, twist) = swingTwistDecomposition(rotation: delta, axis: sourceAxis)
        let signedAngle = signedTwistAngle(twist, around: sourceAxis)
        let clampedAngle = min(max(signedAngle, -maximumRadians), maximumRadians) * twistWeight
        guard abs(clampedAngle) > 0.0001 else {
            return .identity
        }

        return simd_quatf(angle: clampedAngle, axis: targetAxis)
    }

    nonisolated private static func swingTwistDecomposition(
        rotation: simd_quatf,
        axis: SIMD3<Float>
    ) -> (swing: simd_quatf, twist: simd_quatf) {
        let projected = simd_project(SIMD3<Float>(rotation.vector.x, rotation.vector.y, rotation.vector.z), axis)
        let twist = simd_normalize(simd_quatf(vector: SIMD4<Float>(projected.x, projected.y, projected.z, rotation.vector.w)))
        let swing = rotation * twist.inverse
        return (swing, twist)
    }

    nonisolated private static func signedTwistAngle(
        _ twist: simd_quatf,
        around axis: SIMD3<Float>
    ) -> Float {
        let normalizedAxis = simd_dot(SIMD3<Float>(twist.vector.x, twist.vector.y, twist.vector.z), axis) >= 0
            ? axis
            : -axis
        let angle = 2 * atan2(simd_length(SIMD3<Float>(twist.vector.x, twist.vector.y, twist.vector.z)), twist.real)
        return simd_dot(SIMD3<Float>(twist.vector.x, twist.vector.y, twist.vector.z), normalizedAxis) >= 0 ? angle : -angle
    }

    private func torsoReferenceTwistRotation(
        spec: DirectionalBoneSpec,
        pose: AvatarDrivePose,
        tPose: AvatarDrivePose,
        parentRotation: simd_quatf,
        tPoseParentRotation: simd_quatf,
        currentSourceAimLocal: SIMD3<Float>,
        tPoseSourceAimLocal: SIMD3<Float>,
        targetCurrentAimLocal: SIMD3<Float>,
        maximumRadians: Float,
        twistWeight: Float
    ) -> simd_quatf? {
        guard
            let torsoCurrentWorld = torsoReferenceWorldDirection(for: spec, in: pose),
            let torsoTPoseWorld = torsoReferenceWorldDirection(for: spec, in: tPose)
        else {
            return nil
        }

        let torsoCurrentLocal = simd_act(parentRotation.inverse, torsoCurrentWorld)
        let torsoTPoseLocal = simd_act(tPoseParentRotation.inverse, torsoTPoseWorld)

        guard
            let projectedCurrent = Self.projectedUnitVector(torsoCurrentLocal, ontoPlanePerpendicularTo: currentSourceAimLocal),
            let projectedTPose = Self.projectedUnitVector(torsoTPoseLocal, ontoPlanePerpendicularTo: tPoseSourceAimLocal)
        else {
            return nil
        }

        let swungTPoseReference = simd_act(
            Self.rotationAligning(from: tPoseSourceAimLocal, to: currentSourceAimLocal),
            projectedTPose
        )
        guard let normalizedSwungTPoseReference = Self.normalized(swungTPoseReference) else {
            return nil
        }

        let signedAngle = Self.signedAngle(
            from: normalizedSwungTPoseReference,
            to: projectedCurrent,
            around: currentSourceAimLocal
        )
        let clampedAngle = min(max(signedAngle, -maximumRadians), maximumRadians) * twistWeight
        guard abs(clampedAngle) > 0.0001 else {
            return .identity
        }

        return simd_quatf(angle: clampedAngle, axis: targetCurrentAimLocal)
    }

    private func torsoReferenceWorldDirection(
        for spec: DirectionalBoneSpec,
        in pose: AvatarDrivePose
    ) -> SIMD3<Float>? {
        guard let shoulder = pose.worldPosition(for: spec.startJoint) else {
            return nil
        }

        let anchors: [OdoroJointName] = [
            .chest,
            .neck,
            .root,
            spec.oppositeShoulder,
        ]

        for anchor in anchors {
            guard let anchorPosition = pose.worldPosition(for: anchor) else {
                continue
            }
            if let direction = Self.normalized(anchorPosition - shoulder) {
                return direction
            }
        }

        return nil
    }

    private func mappedTargetAimLocal(
        spec: DirectionalBoneSpec,
        binding: AvatarBoneBinding,
        sourceCurrentAimLocal: SIMD3<Float>,
        sourceTPoseAimLocal: SIMD3<Float>,
        targetBindAimLocal: SIMD3<Float>,
        pose: AvatarDrivePose,
        tPose: AvatarDrivePose,
        parentRotation: simd_quatf,
        tPoseParentRotation: simd_quatf
    ) -> SIMD3<Float>? {
        guard spec.usesTorsoReferenceTwist else {
            return nil
        }
        guard
            let sourceTPoseReference = sourceTorsoReferenceLocal(
                spec: spec,
                pose: tPose,
                parentRotation: tPoseParentRotation,
                aimLocal: sourceTPoseAimLocal
            ),
            let sourceCurrentReference = sourceTorsoReferenceLocal(
                spec: spec,
                pose: pose,
                parentRotation: parentRotation,
                aimLocal: sourceCurrentAimLocal
            ),
            let targetBindReference = targetTorsoReferenceLocal(
                for: binding,
                aimLocal: targetBindAimLocal
            )
        else {
            return nil
        }

        let sourceTPoseNormal = simd_normalize(simd_cross(sourceTPoseAimLocal, sourceTPoseReference))
        let targetBindNormal = simd_normalize(simd_cross(targetBindAimLocal, targetBindReference))

        let coords = SIMD3<Float>(
            simd_dot(sourceCurrentAimLocal, sourceTPoseAimLocal),
            simd_dot(sourceCurrentAimLocal, sourceTPoseReference),
            simd_dot(sourceCurrentAimLocal, sourceTPoseNormal)
        )
        let mapped = targetBindAimLocal * coords.x
            + targetBindReference * coords.y
            + targetBindNormal * coords.z
        return Self.normalized(mapped)
    }

    private func sourceTorsoReferenceLocal(
        spec: DirectionalBoneSpec,
        pose: AvatarDrivePose,
        parentRotation: simd_quatf,
        aimLocal: SIMD3<Float>
    ) -> SIMD3<Float>? {
        guard let torsoWorld = torsoReferenceWorldDirection(for: spec, in: pose) else {
            return nil
        }
        let torsoLocal = simd_act(parentRotation.inverse, torsoWorld)
        return Self.projectedUnitVector(torsoLocal, ontoPlanePerpendicularTo: aimLocal)
    }

    private func targetTorsoReferenceLocal(
        for binding: AvatarBoneBinding,
        aimLocal: SIMD3<Float>
    ) -> SIMD3<Float>? {
        guard
            let parentJoint = binding.parentSourceJoint?.canonicalJoint,
            let parentBinding = profile.bindings.first(where: { $0.sourceJoint.canonicalJoint == parentJoint }),
            let parentIndex = modelJointIndices[parentBinding.boneName],
            bindPoseTransforms.indices.contains(parentIndex)
        else {
            return nil
        }

        let parentTransform = bindPoseTransforms[parentIndex]
        let torsoVectorInParentLocal = simd_act(
            parentTransform.rotation.inverse,
            -parentTransform.translation
        )
        return Self.projectedUnitVector(torsoVectorInParentLocal, ontoPlanePerpendicularTo: aimLocal)
    }

    nonisolated private static func projectedUnitVector(
        _ vector: SIMD3<Float>,
        ontoPlanePerpendicularTo axis: SIMD3<Float>
    ) -> SIMD3<Float>? {
        let rejection = vector - simd_project(vector, axis)
        return normalized(rejection)
    }

    nonisolated private static func signedAngle(
        from source: SIMD3<Float>,
        to target: SIMD3<Float>,
        around axis: SIMD3<Float>
    ) -> Float {
        let cross = simd_cross(source, target)
        let sine = simd_dot(cross, axis)
        let cosine = simd_dot(source, target)
        return atan2(sine, cosine)
    }

    private func targetBindDirectionParent(for spec: DirectionalBoneSpec) -> SIMD3<Float>? {
        guard
            let childBinding = profile.bindings.first(where: { $0.sourceJoint.canonicalJoint == spec.childJoint }),
            let childIndex = modelJointIndices[childBinding.boneName],
            bindPoseTransforms.indices.contains(childIndex)
        else {
            return nil
        }

        return Self.normalized(bindPoseTransforms[childIndex].translation)
    }
}

private extension simd_quatf {
    nonisolated static let identity = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
}
