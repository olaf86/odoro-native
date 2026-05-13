# ARKit to VRM 0.x Retargeting Investigation

## Goal

Evaluate whether Odoro can drive a `VRM 0.x` humanoid avatar from `ARKit Body Tracking`
without Unity, using a native iOS stack such as:

1. `ARKit`
2. `RealityKit` or `SceneKit`
3. `VRMKit`

## Short Conclusion

This is feasible in native Swift, but not as an out-of-the-box pipeline.

- `ARKit` gives enough body joints and transforms to drive a coarse humanoid retarget.
- `VRM 0.x` gives a standardized humanoid bone list and normalized T-pose assumptions.
- The missing piece is still a custom retarget solver that handles rest pose deltas,
  coordinate conversion, twist control, and smoothing.
- `VRMKit` is useful for loading and rendering VRM on iOS, but it does not remove the
  need for a project-specific ARKit-to-humanoid solver.

## What Already Exists In Odoro

Odoro already has the right architectural seam for this work.

- `OdoroCanonicalPoseMapper` converts backend-specific ARKit joints into a smaller
  canonical humanoid layer. See [OdoroCanonicalPoseMapper.swift](/Users/olaf/Repos/odoro-native/OdoroNative/Infrastructure/Persistence/OdoroCanonicalPoseMapper.swift:10).
- `OdoroJointName` already describes a minimal body skeleton that is close to the first
  set of bones we would want to drive on a VRM avatar. See [OdoroSkeleton.swift](/Users/olaf/Repos/odoro-native/OdoroNative/Domain/OdoroSkeleton.swift:8).
- `AvatarRigRetargeter` already applies the correct high-level math for rest-pose-aware
  retargeting: local motion delta from source T-pose, then re-application on the model
  bind pose. See [AvatarRigRetargeter.swift](/Users/olaf/Repos/odoro-native/OdoroNative/Infrastructure/AvatarRigRetargeter.swift:10) and [AvatarRigRetargeter.swift](/Users/olaf/Repos/odoro-native/OdoroNative/Infrastructure/AvatarRigRetargeter.swift:112).

In other words, the current codebase is already structured like:

`ARKit -> canonical humanoid -> rig profile -> avatar skeleton`

That is the right shape for `ARKit -> VRM humanoid`.

## Findings

### 1. Native Swift/iOS examples and libraries do exist, but the full retarget path is still custom

- Apple provides `ARSkeleton3D`, `ARSkeletonDefinition.defaultBody3D`, and body tracking
  sample code for driving a rigged character.
- Apple also provides `BodyTrackedEntity`, but it only works directly when the model is
  authored to ARKit's required skeleton and naming conventions.
- `VRMKit` can load VRM files and render them with SceneKit, and it exposes humanoid bones
  for manual bone animation.

Practical implication:

- If the avatar is authored for ARKit's skeleton, RealityKit can do much more for free.
- If the avatar is a generic `VRM 0.x` model, native Swift is still viable, but we own the
  retargeting layer.

### 2. VRM 0.x is standardized enough to generalize the solver, but not enough to skip per-model rig calibration

VRM 0.x helps because it standardizes:

- humanoid bone names
- a normalized humanoid concept
- T-pose assumptions
- meter units

However, it does not fully erase differences in:

- exact bind orientation
- bone roll
- shoulder and arm twist behavior
- leg proportions and foot contact behavior
- optional bones and non-humanoid helper bones

Practical implication:

- One solver can generalize across many `VRM 0.x` avatars.
- Each avatar still benefits from a rig profile with offsets, weights, and optional limits.

### 3. Rest-pose correction is not optional

The most robust baseline is:

`delta = inverse(sourceRestLocal) * sourceCurrentLocal`

`targetLocal = targetRestLocal * delta`

This matches the approach Odoro already uses in `AvatarRigRetargeter`.

### 4. Quaternion copy alone is not stable enough for production

For a minimal prototype, direct local rotation delta is fine.

For a stable avatar driver, the next corrections are usually needed:

- direction-vector reconstruction for upper arm, lower arm, upper leg, and lower leg
- swing-twist decomposition for forearm and lower leg twist cleanup
- hinge-like limits for knees and elbows
- root and head smoothing
- optional foot grounding or post-pass IK

### 5. RealityKit versus SceneKit

For `VRM 0.x`, SceneKit is the easier first target today because `VRMKit` already supports it.

- `RealityKit` is excellent for AR session handling and native body-tracked USD assets.
- `SceneKit` is currently the more direct path for driving loaded VRM humanoid nodes bone by bone.

Practical implication:

- The most realistic native first version is:
  `ARKit capture + canonical pose + custom solver + VRMKit/SceneKit avatar drive`
- A later step could move rendering or scene integration toward RealityKit if needed.

## Recommended Implementation Plan

### Phase 1. Prove the core solver on major bones only

Drive only:

- hips
- spine
- chest or upper chest if present
- neck
- head
- left and right upper arm
- left and right lower arm
- left and right hand
- left and right upper leg
- left and right lower leg
- left and right foot

Do not start with fingers, toes, spring bones, or facial expressions.

### Phase 2. Use a data-driven VRM rig profile

Add a VRM-specific rig profile format that records:

- `vrmHumanoidBone -> runtime node`
- parent source joint
- rest rotation offset
- translation mode
- rotation weight
- optional swing or twist clamp values

This is close to the `AvatarRigProfile` model already present in Odoro.

### Phase 3. Prefer vector reconstruction for limbs

Use ARKit joint positions to reconstruct limb aim when source rotations become unstable.

Good candidates:

- shoulder to elbow
- elbow to wrist
- hip to knee
- knee to ankle

Then combine:

- primary swing from aim vector
- reduced twist from source quaternion or from a filtered roll estimate

### Phase 4. Add post-solve stabilization

Recommended order:

1. root smoothing
2. head smoothing
3. elbow and knee limits
4. forearm twist clamp
5. optional foot planting or IK

## Recommendation On Unity

Avoiding Unity has real value if the goals are:

- small integration surface
- full control of capture and retarget logic in Swift
- tight integration with the existing native Odoro architecture
- shipping a native iOS app without a mixed runtime

Unity becomes more attractive if the goals are:

- fastest path to robust humanoid retargeting across many avatar assets
- VRM ecosystem compatibility out of the box
- mature tooling for constraints, IK, and avatar debugging
- easier iteration on avatar import problems and shader issues

My recommendation:

- Start native.
- Use `ARKit + canonical pose + custom retargeter + VRMKit/SceneKit`.
- Revisit `Unity as Library` only if avatar compatibility, spring bones, shader fidelity,
  or IK quality becomes the main bottleneck instead of motion capture itself.

## Suggested Next Prototype

Build a narrow proof of concept that:

1. loads one known-good `VRM 0.x` avatar with `VRMKit`
2. maps Odoro canonical joints to the VRM humanoid major bones
3. applies rest-pose-corrected local deltas every frame
4. uses position-vector reconstruction for elbows and knees
5. records debug output for per-bone angular error and flip detection

Success criteria:

- standing idle looks stable
- arm raise does not invert forearms
- squat does not reverse knees
- torso rotation does not collapse shoulders

## External References

- Apple ARSkeletonDefinition.defaultBody3D:
  https://developer.apple.com/documentation/arkit/arskeletondefinition/defaultbody3d
- Apple ARSkeleton3D:
  https://developer.apple.com/documentation/arkit/arskeleton3d
- Apple Capturing Body Motion in 3D:
  https://developer.apple.com/documentation/arkit/capturing-body-motion-in-3d
- Apple Rigging a Model for Motion Capture:
  https://developer.apple.com/documentation/arkit/rigging-a-model-for-motion-capture
- Apple Validating a Model for Motion Capture:
  https://developer.apple.com/documentation/arkit/validating-a-model-for-motion-capture
- Apple RealityKit skeletal pose and IK overview:
  https://developer.apple.com/documentation/realitykit/game-development-character-skeletons
- VRMKit:
  https://github.com/tattn/VRMKit
- VRM 0.x specification:
  https://github.com/vrm-c/vrm-specification/blob/master/specification/0.0/README.md
- VRM development notes:
  https://vrm.dev/en/vrm/vrm_development/
- VRM coordinate conversion notes:
  https://vrm.dev/api/coordinate/
