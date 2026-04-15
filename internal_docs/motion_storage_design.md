# Motion Storage Design

## Goal

Odoro stores short motion takes for later recombination into a choreographed 3D performance.
The recording source may vary by platform and capture backend, but the stored format should stay stable across:

- iOS ARKit body tracking
- iOS Vision front camera pose estimation
- future Android pose backends
- local-only usage
- future GCS-backed sync

The app does not need to persist camera video to satisfy product requirements. The durable asset is the motion payload: per-frame joint positions, optional rotations, and optional quality/provenance data.

## Storage Strategy

Use a hybrid storage model:

- SwiftData stores searchable local metadata
- one `.odoro` file stores the full motion payload for each take
- GCS later stores the same `.odoro` file as an object

This keeps the local app responsive while preserving a portable payload that can be uploaded without transformation.

## Entity Model

### RecordingSession

`RecordingSession` is the shared context for multiple takes recorded under the same musical conditions.

Recommended fields:

- `id`
- `createdAt`
- `tempoSourceType`
- `audioAssetReference`
- `bpm`
- `timeSignatureNumerator`
- `timeSignatureDenominator`
- `targetBarCount`
- `countInBarCount`
- `notes`

Rationale:

- musical settings are shared across multiple takes
- repeating these fields on every take would create duplication
- later choreography tools can group takes by session naturally

### MotionTake

`MotionTake` is one recorded clip belonging to a session.

Recommended fields:

- `id`
- `sessionId`
- `createdAt`
- `takeIndex`
- `captureMode`
- `durationSeconds`
- `frameCount`
- `nominalFrameRate`
- `barLength`
- `beatLength`
- `startBeatOffset`
- `isAccepted`
- `localFilePath`
- `uploadStatus`
- `remoteObjectKey`
- `schemaVersion`

Field meanings:

- `barLength`: number of bars represented by the take
- `beatLength`: number of beats represented by the take
- `startBeatOffset`: beat position inside the session timeline where this take starts
- `isAccepted`: whether this take is currently kept as a candidate for choreography

### Motion Payload File

Each take is backed by one `.odoro` file.

The payload should be versioned and portable:

- `schemaVersion`
- `skeletonId`
- `jointNames`
- `jointCount`
- `captureMode`
- `sourcePlatform`
- `sourceBackend`
- `frames`

Each frame should contain:

- `timeSeconds`
- `timeBeats`
- `positions`
- `rotations` optional
- `confidences` optional
- `jointStatuses` optional

## Canonical Skeleton

Persisted payloads should not depend on ARKit joint ordering or backend-native landmark names.
Odoro defines one canonical skeleton for storage.

`OdoroSkeletonV1`:

1. `root`
2. `head`
3. `nose`
4. `leftShoulder`
5. `rightShoulder`
6. `leftElbow`
7. `rightElbow`
8. `leftWrist`
9. `rightWrist`
10. `leftHip`
11. `rightHip`
12. `leftKnee`
13. `rightKnee`
14. `leftAnkle`
15. `rightAnkle`
16. `leftFoot`
17. `rightFoot`

The canonical skeleton is now codified in [OdoroSkeleton.swift](/Users/olaf/Repos/odoro/Odoro/Domain/OdoroSkeleton.swift:1).

### Joint Definitions

- `root`: pelvis center. Prefer a backend-native root when available; otherwise use hip midpoint
- `head`: head representative point. Prefer backend-native head; otherwise derive from nose and shoulder center
- `nose`: face-forward representative point
- `leftWrist` / `rightWrist`: wrist representative points; backends that expose hand instead of wrist may map into these slots
- `leftFoot` / `rightFoot`: forefoot or toe-side representative points; these are Odoro semantic foot endpoints, not necessarily identical native anatomical labels

## Provenance and Quality

Optional per-joint provenance is useful for playback quality and later cleanup.

Recommended `OdoroJointStatus` values:

- `observed`: directly detected by the backend
- `mapped`: one-to-one mapped from a backend joint with a different name
- `derived`: deterministically computed from observed joints
- `inferred`: heuristically estimated because the backend did not provide the joint directly
- `missing`: unavailable

Optional `confidences` represent how trustworthy a stored joint value is.

Typical uses:

- increase smoothing for low-confidence joints
- suppress or repair unstable limbs
- distinguish fully observed ARKit motion from partially inferred front-camera motion

## Backend Mapping Rules

### ARKit rear body tracking

Primary characteristics:

- highest fidelity source in the current app
- native 3D body skeleton
- many joints are directly observed or cleanly mapped

Mapping guidance:

- use native `root` and `head` where available
- map hand-like joints into canonical wrist slots
- map lower-body joints directly
- mark canonical joints as `observed` or `mapped`

### Vision front camera pose

Primary characteristics:

- strongest on upper body and nose
- lower body may be incomplete or reconstructed

Mapping guidance:

- shoulders, elbows, wrists, and nose are primary observed joints
- hips should use observed body-pose hips when available
- `root` derives from hip midpoint
- `head` derives from nose and shoulder center unless a better source exists
- knees, ankles, and feet may be `inferred`

### Future Android backend

Expected characteristics:

- ML Kit / MediaPipe style landmark sets
- strong compatibility with shoulders, elbows, wrists, hips, knees, ankles, and nose

Mapping guidance:

- map direct landmarks into canonical slots
- derive `head` from nose and shoulder center if needed
- map toe or foot-index style landmarks into canonical foot slots

## Why Array-Centered Payloads

The payload should store frame data as arrays in canonical index order, not as repeated joint-name structs per frame.

Recommended shape:

- one payload header with canonical `jointNames`
- each frame stores `positions[17]`
- `rotations[17]?`
- `confidences[17]?`
- `jointStatuses[17]?`

Advantages:

- smaller files
- faster decode and batch processing
- aligns with current app rendering model
- better suited for future GCS object storage

Tradeoff:

- payloads are less human-readable than per-joint structs

This is acceptable because the header carries the canonical joint name ordering.

## Local Persistence Plan

Phase 1 local persistence should work like this:

1. create or select a `RecordingSession`
2. record one take
3. transform backend-native joints into `OdoroSkeletonV1`
4. write one `.odoro` payload file under `Application Support/Clips/`
5. create one SwiftData `MotionTake` row that points at the file
6. load saved takes for stage playback by reading metadata first, then decoding the payload file on demand

## GCS Plan

GCS should treat each `.odoro` file as the canonical object.

Recommended approach:

- keep local payload and cloud payload byte-compatible
- upload by object key derived from session and take IDs
- store upload state and remote key in `MotionTake`
- prefer signed-URL upload flow once backend infrastructure exists

## Recommended Implementation Order

1. persist the canonical skeleton definition in code
2. add backend-to-canonical mapping layer
3. define the `.odoro` payload schema in Swift types
4. add local file writer and reader
5. add SwiftData models for `RecordingSession` and `MotionTake`
6. switch stage playback to load from saved takes
7. add GCS sync later without changing payload format

## Final Recommendation

Proceed with:

- `RecordingSession` and `MotionTake` as separate entities
- one canonical skeleton: `OdoroSkeletonV1`
- one portable payload file per take
- array-centered frame storage
- optional rotations, confidences, and joint statuses
- SwiftData for metadata only
- GCS as a later transport and sync layer, not the source-of-truth schema

This design is stable enough to begin implementation without locking the app to Apple-native joint orderings or to a single capture backend.
