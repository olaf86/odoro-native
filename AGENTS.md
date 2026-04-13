# AGENTS.md

This file provides guidance to Codex (Codex.ai/code) when working with code in this repository.

## Build & Test Commands

```bash
# Build (Debug)
xcodebuild -project Odoro.xcodeproj -scheme Prod -configuration Debug

# Run unit tests
xcodebuild -project Odoro.xcodeproj -scheme Stg -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.4' -only-testing:OdoroTests test

# Build for release
xcodebuild -project Odoro.xcodeproj -scheme Prod -configuration Production archive
```

The app requires iOS 26.4+. ARKit body tracking and Vision pose detection require a physical device — only the `mock` capture mode runs in Simulator.

## Architecture

Odoro is a dance motion capture and playback app using Clean Architecture with four layers:

**Domain** (`Odoro/Domain/`) — Protocols and models only, no framework imports:
- `MotionSource` protocol: the extension point for all capture backends
- `MotionFrame` / `MotionClip`: core data structures using `SIMD3<Float>` joint arrays
- `MotionStudioState` / `StudioPresentation`: UI state enums

**Infrastructure** (`Odoro/Infrastructure/`) — Concrete `MotionSource` implementations:
- `ARKitMotionSource`: rear camera full-body tracking via `ARBodyTrackingConfiguration`
- `VisionFrontCameraMotionSource`: front camera upper-body pose via `VNDetectHumanBodyPoseRequest`
- `MockMotionSource`: procedural sine-wave animation for Simulator and previews
- `StagePlaybackRenderer`: RealityKit renderer — joints as spheres, limbs as boxes

**Application** (`Odoro/Application/`) — `MotionStudioInteractor` drives the recording state machine, collects `MotionFrame`s from whatever source is active, caps capture at 10 seconds, and normalizes the resulting `MotionClip` (origin at foot level, first frame as reference).

**Presentation** (`Odoro/Presentation/` + `ContentView.swift`) — `StudioViewModel` (@Observable) selects the active `MotionSource` implementation at runtime and owns `MotionStudioInteractor`. Views are `UIViewRepresentable` wrappers around ARView / AVCaptureSession / RealityKit scene.

## Adding a New Motion Source

1. Create a new file in `Odoro/Infrastructure/` conforming to `MotionSource`.
2. Add a case to the `CaptureMode` enum in `Domain/MotionSource.swift`.
3. Wire the case in `StudioViewModel.swift` where the active source is instantiated.
4. Add the corresponding capture preview view in `ContentView.swift` if a camera feed is needed.

## Key Conventions

- Joint positions are world-space `SIMD3<Float>`; index order matches `ARSkeleton.JointName` ordering used in `ARKitMotionSource`.
- Playback is fixed at 30 FPS (`1.0/30` second intervals in `MotionStudioInteractor`).
- `StagePlaybackRenderer` falls back to procedural mock rendering if a clip has fewer than 2 frames or zero joints — useful to know when debugging rendering issues.
- `StudioViewModel` guards mode switching on `#if targetEnvironment(simulator)` so Mock is the only option in Simulator builds.
