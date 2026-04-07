//
//  ContentView.swift
//  Visco
//
//  Created by Yuta Ogawa on 2026/04/07.
//

import ARKit
import Combine
import RealityKit
import SwiftData
import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var studio = MotionStudioModel()

    var body: some View {
        Group {
            if studio.isSupported {
                switch studio.presentation {
                case .capture:
                    CaptureExperienceView(studio: studio)
                case .stage:
                    StageExperienceView(studio: studio)
                }
            } else {
                UnsupportedBodyTrackingView()
            }
        }
    }
}

private struct CaptureExperienceView: View {
    @ObservedObject var studio: MotionStudioModel

    var body: some View {
        ZStack {
            MotionCaptureARView(studio: studio)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 14) {
                Text("Visco Capture")
                    .font(.headline)

                Text(studio.statusText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 16) {
                    Label("\(studio.recordedFrameCount) frames", systemImage: "figure.dance")
                    Label(studio.recordingDurationText, systemImage: "clock")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Text("背面カメラで全身を捉え、短い振り付けを収録します。停止するとステージ再生に切り替わります。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    Button(studio.isRecording ? "Recording..." : "Start Capture") {
                        studio.beginRecording()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(studio.isRecording)

                    Button("Stop") {
                        studio.stopRecording()
                    }
                    .buttonStyle(.bordered)
                    .disabled(!studio.isRecording)

                    Button("Replay Stage") {
                        studio.enterStageMode()
                    }
                    .buttonStyle(.bordered)
                    .disabled(!studio.hasClip)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(alignment: .topLeading) {
                LinearGradient(
                    colors: [Color.black.opacity(0.78), Color.black.opacity(0.08)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 220)
                .ignoresSafeArea()
            }
        }
    }
}

private struct StageExperienceView: View {
    @ObservedObject var studio: MotionStudioModel

    var body: some View {
        ZStack {
            StagePlaybackView(studio: studio)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 14) {
                Text("Visco Stage")
                    .font(.headline)

                Text(studio.statusText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 16) {
                    Label(studio.clipDurationText, systemImage: "music.note")
                    Label("\(studio.recordedFrameCount) frames", systemImage: "film")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Text("収録した関節位置を簡易ダンサーとしてループ再生しています。将来的にはリグ済みキャラクターへ置き換える前提のモックです。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    Button(studio.isPlaying ? "Pause" : "Play") {
                        studio.togglePlayback()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!studio.hasClip)

                    Button("Record Again") {
                        studio.returnToCapture()
                    }
                    .buttonStyle(.bordered)

                    Button("Reset Clip") {
                        studio.resetClip()
                    }
                    .buttonStyle(.bordered)
                    .disabled(!studio.hasClip)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(alignment: .topLeading) {
                LinearGradient(
                    colors: [Color.black.opacity(0.82), Color.black.opacity(0.12)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 220)
                .ignoresSafeArea()
            }
        }
        .onAppear {
            studio.prepareStagePlayback()
        }
        .onDisappear {
            studio.pausePlayback()
        }
    }
}

private struct UnsupportedBodyTrackingView: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.08, green: 0.1, blue: 0.16), Color.black],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 16) {
                Text("Body Tracking Unsupported")
                    .font(.title2.weight(.semibold))

                Text("このモックは `ARBodyTrackingConfiguration` を使います。A12 以降の実機 iPhone / iPad で確認してください。")
                    .foregroundStyle(.secondary)
            }
            .padding(24)
        }
    }
}

private struct MotionCaptureARView: UIViewRepresentable {
    @ObservedObject var studio: MotionStudioModel

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
        studio.attachCaptureView(view)
        return view
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        studio.updateCaptureView(uiView)
    }
}

private struct StagePlaybackView: UIViewRepresentable {
    @ObservedObject var studio: MotionStudioModel

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        studio.attachStageView(view)
        return view
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        studio.updateStageView(uiView)
    }
}

private enum StudioPresentation {
    case capture
    case stage
}

private struct CapturedPoseFrame {
    let time: TimeInterval
    let jointPositions: [SIMD3<Float>]
}

@MainActor
private final class MotionStudioModel: NSObject, ObservableObject {
    @Published var presentation: StudioPresentation = .capture
    @Published var statusText = "全身が映る位置に立ってください"
    @Published var isRecording = false
    @Published var isPlaying = false
    @Published var recordedFrameCount = 0
    @Published var recordingDuration: TimeInterval = 0
    @Published var clipDuration: TimeInterval = 0

    let isSupported = ARBodyTrackingConfiguration.isSupported

    var hasClip: Bool {
        !playbackFrames.isEmpty
    }

    var recordingDurationText: String {
        recordingDuration.formatted(.number.precision(.fractionLength(1))) + "s"
    }

    var clipDurationText: String {
        clipDuration.formatted(.number.precision(.fractionLength(1))) + "s clip"
    }

    private let skeletonDefinition = ARSkeletonDefinition.defaultBody3D
    private lazy var limbPairs: [(Int, Int)] = {
        skeletonDefinition.parentIndices.enumerated().compactMap { childIndex, parentIndex in
            guard parentIndex >= 0 else {
                return nil
            }
            return (parentIndex, childIndex)
        }
    }()

    private weak var captureView: ARView?
    private weak var stageView: ARView?

    private var captureFrames: [CapturedPoseFrame] = []
    private var playbackFrames: [CapturedPoseFrame] = []
    private var recordingStartTimestamp: TimeInterval?
    private var playbackTimer: Timer?
    private var playbackStartedAt: Date?

    private var stageAnchor = AnchorEntity()
    private var dancerRoot = Entity()
    private var jointEntities: [ModelEntity] = []
    private var limbEntities: [ModelEntity] = []

    private let maximumCaptureDuration: TimeInterval = 10

    func attachCaptureView(_ view: ARView) {
        captureView = view
        view.session.delegate = self
        startBodyTrackingSession(in: view)
    }

    func updateCaptureView(_ view: ARView) {
        if captureView !== view {
            attachCaptureView(view)
        }
    }

    func attachStageView(_ view: ARView) {
        stageView = view
        configureStageScene(in: view)
    }

    func updateStageView(_ view: ARView) {
        if stageView !== view {
            attachStageView(view)
        }
    }

    func beginRecording() {
        guard isSupported else { return }
        if presentation != .capture {
            returnToCapture()
        }

        captureFrames.removeAll()
        recordingStartTimestamp = nil
        recordedFrameCount = 0
        recordingDuration = 0
        isRecording = true
        statusText = "収録中です。全身が入るように動いてください"
    }

    func stopRecording() {
        guard isRecording else { return }

        isRecording = false

        guard captureFrames.count > 1 else {
            statusText = "十分な動きを収録できませんでした。もう一度試してください"
            return
        }

        playbackFrames = normalizeForStage(captureFrames)
        clipDuration = playbackFrames.last?.time ?? 0
        statusText = "収録完了。ステージで再生できます"
        presentation = .stage
    }

    func enterStageMode() {
        guard hasClip else { return }
        presentation = .stage
    }

    func returnToCapture() {
        pausePlayback()
        presentation = .capture
        statusText = hasClip ? "収録済みクリップがあります。必要なら上書きできます" : "全身が映る位置に立ってください"
        if let captureView {
            startBodyTrackingSession(in: captureView)
        }
    }

    func resetClip() {
        pausePlayback()
        captureFrames.removeAll()
        playbackFrames.removeAll()
        recordingStartTimestamp = nil
        recordedFrameCount = 0
        recordingDuration = 0
        clipDuration = 0
        presentation = .capture
        statusText = "クリップをリセットしました。新しく収録できます"
    }

    func prepareStagePlayback() {
        guard hasClip else { return }
        captureView?.session.pause()
        configureStageSceneIfNeeded()
        startPlayback()
    }

    func togglePlayback() {
        isPlaying ? pausePlayback() : startPlayback()
    }

    func pausePlayback() {
        playbackTimer?.invalidate()
        playbackTimer = nil
        playbackStartedAt = nil
        isPlaying = false
    }

    private func startBodyTrackingSession(in view: ARView) {
        guard isSupported else { return }

        let configuration = ARBodyTrackingConfiguration()
        configuration.isAutoFocusEnabled = true
        configuration.automaticSkeletonScaleEstimationEnabled = true
        view.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }

    private func consumeTrackedFrame(_ trackedFrame: CapturedPoseFrame) {
        statusText = isRecording ? "収録中です。ステージ用に動きを保存しています" : "人物を検出しました。収録を開始できます"

        guard isRecording else { return }

        if recordingStartTimestamp == nil {
            recordingStartTimestamp = trackedFrame.time
        }

        let relativeTime = trackedFrame.time - (recordingStartTimestamp ?? trackedFrame.time)
        let frame = CapturedPoseFrame(time: relativeTime, jointPositions: trackedFrame.jointPositions)
        captureFrames.append(frame)
        recordedFrameCount = captureFrames.count
        recordingDuration = relativeTime

        if relativeTime >= maximumCaptureDuration {
            stopRecording()
        }
    }

    private func configureStageSceneIfNeeded() {
        guard let stageView else { return }
        if stageView.scene.anchors.isEmpty {
            configureStageScene(in: stageView)
        }
    }

    private func configureStageScene(in view: ARView) {
        pausePlayback()

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

        if let firstFrame = playbackFrames.first {
            render(frame: firstFrame)
        }
    }

    private func buildDancerHierarchy() {
        let jointCount = skeletonDefinition.jointNames.count

        for _ in 0..<jointCount {
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

    private func startPlayback() {
        guard hasClip else { return }

        configureStageSceneIfNeeded()
        pausePlayback()
        isPlaying = true
        playbackStartedAt = Date()

        render(frame: playbackFrames[0])

        playbackTimer = Timer.scheduledTimer(
            timeInterval: 1 / 30,
            target: self,
            selector: #selector(handlePlaybackTimer),
            userInfo: nil,
            repeats: true
        )
    }

    @objc private func handlePlaybackTimer() {
        advancePlayback()
    }

    private func advancePlayback() {
        guard
            isPlaying,
            let playbackStartedAt,
            let duration = playbackFrames.last?.time,
            duration > 0
        else {
            return
        }

        let elapsed = Date().timeIntervalSince(playbackStartedAt).truncatingRemainder(dividingBy: duration)
        let frame = playbackFrames.last { $0.time <= elapsed } ?? playbackFrames[0]
        render(frame: frame)
    }

    private func render(frame: CapturedPoseFrame) {
        guard frame.jointPositions.count == jointEntities.count else {
            return
        }

        for (index, jointEntity) in jointEntities.enumerated() {
            let position = frame.jointPositions[index]
            jointEntity.position = position
            jointEntity.isEnabled = position.x.isFinite && position.y.isFinite && position.z.isFinite
        }

        for (index, pair) in limbPairs.enumerated() {
            let parent = frame.jointPositions[pair.0]
            let child = frame.jointPositions[pair.1]
            let delta = child - parent
            let length = simd_length(delta)
            let limb = limbEntities[index]

            guard length > 0.0001 else {
                limb.isEnabled = false
                continue
            }

            limb.isEnabled = true
            limb.position = (parent + child) * 0.5
            limb.orientation = simd_quatf(from: SIMD3<Float>(0, 1, 0), to: simd_normalize(delta))
            limb.scale = [1, length, 1]
        }
    }

    private func normalizeForStage(_ frames: [CapturedPoseFrame]) -> [CapturedPoseFrame] {
        guard let firstFrame = frames.first else {
            return []
        }

        let firstAverage = firstFrame.jointPositions.reduce(SIMD3<Float>.zero, +) / Float(firstFrame.jointPositions.count)
        let floorHeight = frames
            .flatMap(\.jointPositions)
            .map(\.y)
            .min() ?? 0

        let origin = SIMD3<Float>(firstAverage.x, floorHeight, firstAverage.z)

        return frames.map { frame in
            let normalizedJoints = frame.jointPositions.map { $0 - origin }
            return CapturedPoseFrame(time: frame.time, jointPositions: normalizedJoints)
        }
    }

    nonisolated private static func makeTrackedFrame(from bodyAnchor: ARBodyAnchor, timestamp: TimeInterval) -> CapturedPoseFrame {
        let worldTransform = bodyAnchor.transform
        let positions = bodyAnchor.skeleton.jointModelTransforms.map { jointTransform in
            let finalTransform = simd_mul(worldTransform, jointTransform)
            let translation = finalTransform.columns.3
            return SIMD3<Float>(translation.x, translation.y, translation.z)
        }

        return CapturedPoseFrame(time: timestamp, jointPositions: positions)
    }
}

extension MotionStudioModel: ARSessionDelegate {
    nonisolated func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        guard let bodyAnchor = anchors.compactMap({ $0 as? ARBodyAnchor }).first else {
            Task { @MainActor in
                if self.isRecording {
                    self.statusText = "人物を見失いました。全身が入る位置へ戻ってください"
                }
            }
            return
        }

        let timestamp = session.currentFrame?.timestamp ?? ProcessInfo.processInfo.systemUptime
        let frame = Self.makeTrackedFrame(from: bodyAnchor, timestamp: timestamp)

        Task { @MainActor in
            self.consumeTrackedFrame(frame)
        }
    }

    nonisolated func session(_ session: ARSession, didFailWithError error: any Error) {
        Task { @MainActor in
            self.statusText = "AR セッションに失敗しました: \(error.localizedDescription)"
        }
    }

    nonisolated func sessionWasInterrupted(_ session: ARSession) {
        Task { @MainActor in
            self.statusText = "AR セッションが中断されました"
        }
    }

    nonisolated func sessionInterruptionEnded(_ session: ARSession) {
        Task { @MainActor in
            self.statusText = "AR セッションが再開しました"
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Item.self, inMemory: true)
}
