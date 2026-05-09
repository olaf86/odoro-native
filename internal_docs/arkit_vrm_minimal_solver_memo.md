# ARKit to VRM Minimal Solver Memo

## Purpose

This note captures the minimum solver shape we want for the first native
`ARKit -> Humanoid -> VRM 0.x` prototype, so we can refer back to it while the
implementation is still moving.

## Current Canonical Joints

For the current experiment, the canonical skeleton is kept in `v1` and uses:

- `root`
- `spine`
- `chest`
- `neck`
- `head`
- `leftShoulder`, `rightShoulder`
- `leftUpperArm`, `rightUpperArm`
- `leftElbow`, `rightElbow`
- `leftWrist`, `rightWrist`
- `leftHip`, `rightHip`
- `leftKnee`, `rightKnee`
- `leftAnkle`, `rightAnkle`
- `leftFoot`, `rightFoot`

`nose` was removed because it was mainly a facing hint and not a core humanoid
retarget joint.

## First Bone Set To Drive

The first solver should only drive major humanoid bones:

- `hips`
- `spine`
- `chest`
- `neck`
- `head`
- `leftUpperArm`, `rightUpperArm`
- `leftLowerArm`, `rightLowerArm`
- `leftHand`, `rightHand`
- `leftUpperLeg`, `rightUpperLeg`
- `leftLowerLeg`, `rightLowerLeg`
- `leftFoot`, `rightFoot`

Do not start with fingers, toes, facial blendshapes, spring bones, or full-body IK.

## Core Retarget Equation

We do not copy source quaternions directly.

Instead we move the change from the source rest pose onto the target rest pose.

```text
sourceLocalNow  = inverse(sourceParentWorldNow) * sourceWorldNow
sourceLocalRest = inverse(sourceParentWorldRest) * sourceWorldRest
delta           = inverse(sourceLocalRest) * sourceLocalNow
targetLocalNow  = targetLocalRest * delta
```

Meaning:

- `sourceLocalRest` is how the source joint sits in the neutral pose
- `sourceLocalNow` is how the source joint sits right now
- `delta` is the motion we actually want to transfer
- `targetLocalRest * delta` applies that motion on top of the avatar bind pose

This is the baseline for stable retargeting across different skeletons.

## Why Direct Quaternion Copy Fails

Direct copy usually breaks because source and target differ in:

- local axis orientation
- bind pose orientation
- parent hierarchy details
- bone roll
- twist distribution

Even if both rigs have a bone named "upper arm", the same quaternion can mean
different visible motion.

## Swing And Twist

Think of a limb rotation as two parts:

- `swing`: changes the direction the bone points
- `twist`: rotates around the bone's own long axis

Examples:

- raising an arm forward is mostly `swing`
- twisting a forearm like turning a doorknob is mostly `twist`

The important implementation rule:

- trust `swing` more than `twist`

ARKit position data is usually good enough to reconstruct limb direction, while
bone-axis twist is much noisier.

## Direction Vector Reconstruction

For major limbs, compute the bone direction from positions:

- upper arm: `shoulder -> elbow`
- forearm: `elbow -> wrist`
- upper leg: `hip -> knee`
- lower leg: `knee -> ankle`

That direction gives the main orientation we want.

In practice:

1. take the model's bind-pose bone axis
2. rotate it so it points to the measured direction
3. use that as the main `swing`

This is usually more stable than trusting the captured quaternion alone.

## Swing/Twist Blend Strategy

For forearms and lower legs, the simplest useful strategy is:

1. build `swing` from the direction vector
2. extract `twist` from the source delta quaternion
3. clamp the twist angle
4. rebuild the final local rotation

Conceptually:

```text
finalLocal = targetRestLocal * swing * clampedTwist
```

This keeps the limb aiming correct while preventing unstable roll.

## Twist Clamp

Twist clamp means limiting how much the solver may rotate around a bone's long axis.

Why:

- ARKit often over-rotates or jitters forearm roll
- a VRM avatar may show that noise very clearly

Typical use:

- forearm twist: allow some rotation, but not a full spin
- lower leg twist: allow very little

Exact angles should stay data-driven in the rig profile.

## Hinge Constraints

Elbows and knees are close to one-axis joints.

Without constraints, quaternion retargeting may produce:

- knees bending sideways
- elbows opening outward
- reversed knee bends

So the solver should treat them like hinge joints:

- preserve the bend axis
- remove most off-axis freedom
- clamp the bend angle to a human range

## Recommended First Solver Order

Per frame:

1. update canonical pose from capture
2. compute source local rotations relative to source parents
3. compute rest-pose delta
4. for limbs, reconstruct swing from joint directions
5. extract and clamp twist where needed
6. rebuild target local rotations from target rest pose
7. smooth root and head
8. apply optional elbow and knee limits

## Recommended Bone Priorities

Implement in this order:

1. root / hips
2. spine / chest / neck / head
3. upper arms
4. forearms
5. upper legs
6. lower legs
7. hands and feet

This lets us debug the torso and limb chain before spending time on smaller details.

## Practical Rule Of Thumb

For the first native prototype:

- positions decide where limbs point
- quaternions provide extra rotational detail
- twist is treated as suspicious until proven stable

That bias should give a much more robust first result than a pure quaternion copy.
