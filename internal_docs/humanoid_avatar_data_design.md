# Humanoid Avatar Data Design

## Goal

Odoro should keep motion capture data and 3D avatar assets loosely coupled.

We want this pipeline:

1. ARKit input
2. ARKit skeleton adapter
3. canonical humanoid representation
4. model adapter per avatar rig
5. bone application on the selected model

This separation lets us:

- keep recorded motion portable
- support both `robot.usdz` and imported VRoid-derived assets
- download only the avatar assets the user actually needs
- swap rendering targets without changing saved motion files

## Design Principles

- Motion data is the source of truth for choreography and playback timing.
- Avatar assets are replaceable presentation resources.
- Rig mapping is versioned data, not renderer-only hardcoded logic.
- Built-in avatars and downloaded avatars should flow through the same selection model.
- A take should never duplicate a full 3D asset inside its saved payload.

## Layered Model

### 1. Capture Layer

Current app responsibility:

- `ARKitMotionSource`
- `VisionFrontCameraMotionSource`
- `MockMotionSource`

Output:

- `MotionFrame`
- later persisted as canonical `MotionPayload`

Notes:

- this layer is backend-specific
- joint order may still reflect backend-native conventions

### 2. Canonical Humanoid Layer

Current app responsibility:

- `OdoroCanonicalPoseMapper`
- `OdoroSkeletonDefinition`

Canonical object:

- `OdoroSkeletonDefinition.id`
- canonical joint names
- optional statuses / confidence / rotations

This is the stable seam between capture and rendering.

A recorded take should continue to store only this canonical motion representation, not model-specific bones.

### 3. Avatar Rig Layer

New responsibility:

- define how one avatar rig consumes canonical joints

Recommended core type:

- `AvatarRigProfile`

Recommended fields:

- `id`
- `displayName`
- `skeletonId`
- `sourceFormat`
- `runtimeFormat`
- `rootBoneName`
- `bindings`
- `restPoseCorrections`
- `scaleCompensation`
- `floorOffset`
- `coordinateSpace`
- `schemaVersion`

`bindings` should be an array of `AvatarBoneBinding`:

- `canonicalJoint`: `OdoroJointName`
- `boneName`: model bone name
- `rotationOffset`
- `translationMode`
- `weight`
- `parentBoneName` optional

Why this layer matters:

- `robot.usdz` and VRoid/glb will have different bone names
- some joints are driven by rotation only, others need translation
- retargeting corrections should be data-driven so the renderer stays small

### 4. Avatar Asset Layer

New responsibility:

- define which avatar packages exist and where they come from

Recommended catalog type:

- `AvatarCatalogItem`

Recommended fields:

- `id`
- `slug`
- `displayName`
- `authorName`
- `thumbnailURL`
- `previewVideoURL` optional
- `defaultRigProfileID`
- `defaultVariantID`
- `availableVariants`
- `tags`
- `isBundled`

Recommended variant type:

- `AvatarAssetVariant`

Recommended fields:

- `id`
- `avatarID`
- `version`
- `runtimeAssetRemoteURL`
- `runtimeAssetChecksum`
- `runtimeAssetSizeBytes`
- `runtimeAssetRelativePath`
- `rigProfileRelativePath`
- `minimumAppVersion`
- `minimumOSVersion`
- `status`

Important distinction:

- `AvatarCatalogItem` is searchable metadata
- `AvatarAssetVariant` points to one installable package version

## Local Storage Responsibilities

We should split local data into three buckets.

### A. Motion Library

Already present:

- SwiftData metadata for takes and sessions
- `.odoro` payload files

This remains independent from avatar files.

### B. Avatar Catalog Cache

Recommended storage:

- one remote manifest JSON cache under `Application Support/AvatarCatalog/`
- optional SwiftData mirror if we need rich filtering offline

Purpose:

- list available avatars
- know file sizes before download
- decide whether an installed version is outdated

### C. Installed Avatar Assets

Recommended file layout:

`Application Support/AvatarAssets/<avatarID>/<version>/`

Contents per installed package:

- runtime model file
- rig profile JSON
- thumbnails or preview media if needed
- optional physics / material sidecar files later

This keeps deletion simple: remove one version directory.

## Download Model

The app should support both bundled and on-demand avatars.

### Bundled

Recommended initial bundled asset:

- `robot.usdz`

Why:

- guaranteed fallback
- works offline
- useful when no downloaded avatar is installed yet

### Downloaded

Recommended initial downloaded assets:

- VRoid-based avatar A
- VRoid-based avatar B

Operational rule:

- ship lightweight catalog metadata
- download the selected avatar package only when the user chooses it
- keep the package versioned and checksum-verified

Recommended package boundary:

- one avatar variant per downloadable archive

That archive should contain at least:

- runtime-ready model
- rig profile
- thumbnail
- manifest metadata for integrity

## Runtime Selection Model

The current `StageAvatarStyle` enum is enough for prototype switching, but it is too small for a catalog-based system.

Recommended replacement direction:

- `StageAvatarSelection`

Suggested shape:

- `kind`: `proceduralSkeleton` or `avatar`
- `avatarID` optional
- `variantID` optional
- `source`: bundled or downloaded

This lets playback choose between:

- skeleton preview
- bundled robot
- downloaded VRoid avatar

without coupling UI state to hardcoded enum cases.

## Take Metadata vs Avatar Metadata

A take should not own the avatar asset.

Recommended rule:

- a `MotionTake` stores the motion only
- playback state stores the current avatar selection
- if we later want per-take default presentation, store only `preferredAvatarID` and `preferredVariantID`

Do not store:

- embedded model binary
- per-bone retargeted transforms inside the take file

Reason:

- the same motion should drive multiple avatars
- asset updates should not invalidate recorded takes
- storage cost stays bounded

## Retargeting Flow

Recommended runtime flow:

1. load canonical `MotionClip`
2. load selected `AvatarRigProfile`
3. map canonical joints to avatar bone targets
4. apply per-binding correction
5. write final transforms into the renderer

Suggested runtime types:

- `CanonicalHumanoidPose`
- `AvatarRigProfile`
- `AvatarRetargetPose`
- `AvatarRetargeter`

Renderer responsibility should stay narrow:

- scene setup
- asset loading
- applying already-resolved bone transforms
- fallback display if the avatar is unavailable

Retargeting math should live outside `StagePlaybackRenderer`.

## Minimal Manifest Proposal

One remote catalog manifest can describe all downloadable avatars.

Suggested top-level fields:

- `schemaVersion`
- `generatedAt`
- `avatars`

Each avatar entry should include:

- catalog metadata
- available variants
- URLs and checksums
- compatibility gates

Each installed variant should also write a local `install.json` with:

- `avatarID`
- `variantID`
- `version`
- `installedAt`
- `checksum`

This makes repair and cleanup straightforward.

## GCS Draft Layout

Recommended object layout in GCS:

- `catalogs/avatar-catalog.production.json`
- `avatars/avatar-sample-a/1.0.0/model.glb`
- `avatars/avatar-sample-a/1.0.0/rig_profile.json`
- `avatars/avatar-sample-a/1.0.0/package_manifest.json`
- `avatars/avatar-sample-b/1.0.0/model.glb`
- `avatars/avatar-sample-b/1.0.0/rig_profile.json`
- `avatars/avatar-sample-b/1.0.0/package_manifest.json`

Recommended rule:

- the catalog manifest is the only file the app needs to know up front
- each avatar variant then points to direct GCS object URLs for `model.glb`, `rig_profile.json`, and `package_manifest.json`
- bundled assets such as `robot.usdz` stay local and do not need to appear in the remote GCS catalog
- the bucket root should come from app configuration such as an Info.plist-backed `AppConfiguration`, not from hardcoded avatar IDs in code
- the real bucket URL should be injected from a gitignored local config such as `Configs/AvatarStorage.local.xcconfig`

This keeps GCS hosting simple while leaving room to switch to signed URLs later.

## How This Fits the Current Codebase

Current code already has a strong seam here:

- capture side emits `MotionFrame`
- persistence side stores canonical motion via `MotionPayload`
- stage side currently hardcodes robot rig logic in `StagePlaybackRenderer`

Recommended refactor boundary:

1. keep `MotionPayload` as the canonical saved format
2. extract robot-specific joint mapping from `StagePlaybackRenderer`
3. introduce a general `AvatarRigProfile`
4. make stage playback load one selected avatar package
5. keep `proceduralSkeleton` as the no-asset fallback

## Recommended SwiftData Additions

If we want local query support, add lightweight metadata models only.

Recommended optional model:

- `AvatarInstallRecord`

Suggested fields:

- `avatarID`
- `variantID`
- `displayName`
- `installedVersion`
- `installState`
- `installedAt`
- `lastUsedAt`
- `sizeBytes`
- `localRootPath`

Do not put the full rig profile into SwiftData.

Store heavy and versioned asset data as files.

## Implementation Order

1. Introduce a catalog-level avatar selection model in domain or presentation.
2. Extract robot rig mapping into a data-driven rig profile.
3. Define file schemas for `avatar_manifest.json` and `rig_profile.json`.
4. Add local avatar installer and remover.
5. Teach stage playback to load bundled and downloaded avatar packages through one interface.
6. Add the two VRoid variants to the catalog as on-demand assets.

## Open Decisions

- whether runtime assets should stay as `glb` or be converted into a format better aligned with the iOS runtime loader
- whether one VRoid source file maps one-to-one to one installable variant, or whether we keep separate low/high quality variants
- whether avatar selection is global app state or remembered per saved take

## Recommendation

For this repository, the safest next step is:

1. keep motion persistence exactly as-is
2. move avatar concerns into a separate asset catalog and rig-profile system
3. treat `robot.usdz` as bundled fallback
4. register the two VRoid/glb models as download-only variants

This matches the desired architecture while keeping storage growth under control.
