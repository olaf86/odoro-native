//
//  ContentView.swift
//  Odoro
//
//  Created by Yuta Ogawa on 2026/04/07.
//

import ARKit
import RealityKit
import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var studio: StudioViewModel

    init(
        archiveStore: MotionArchiveStore? = nil,
        recordingContext: MotionRecordingContext? = nil
    ) {
        _studio = StateObject(
            wrappedValue: StudioViewModel(
                archiveStore: archiveStore,
                recordingContext: recordingContext
            )
        )
    }

    var body: some View {
        Group {
            switch studio.presentation {
            case .capture:
                CaptureExperienceView(studio: studio)
            case .stage:
                StageExperienceView(studio: studio)
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                studio.prepareCapturePreviewIfNeeded()
            case .inactive, .background:
                studio.suspendStudioForInactivity()
            @unknown default:
                break
            }
        }
    }
}

private struct CaptureExperienceView: View {
    @ObservedObject var studio: StudioViewModel

    var body: some View {
        ZStack {
            if studio.usesMockSource {
                MockCapturePreviewView()
            } else if studio.usesFrontCameraSource {
                FrontCameraCaptureView(studio: studio)
            } else {
                MotionCaptureARView(studio: studio)
            }

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    Text(L10n.captureTitle)
                        .font(.headline)
                        .foregroundStyle(.white)

                    Text(studio.statusText)
                        .font(.subheadline)
                        .foregroundStyle(Color.white.opacity(0.9))

                    Picker(L10n.captureModeLabel, selection: Binding(
                        get: { studio.captureMode },
                        set: { studio.selectCaptureMode($0) }
                    )) {
                        ForEach(studio.availableCaptureModes) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(studio.isRecording)

                    HStack(spacing: 16) {
                        Label(L10n.frames(studio.recordedFrameCount), systemImage: "figure.dance")
                        Label(studio.recordingDurationText, systemImage: "clock")
                    }
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(0.78))

                    if studio.usesMockSource {
                        Text(L10n.captureHintMock)
                            .font(.caption)
                            .foregroundStyle(Color.white.opacity(0.78))
                    } else if studio.usesFrontCameraSource {
                        Text(L10n.captureHintFront)
                            .font(.caption)
                            .foregroundStyle(Color.white.opacity(0.78))
                    } else {
                        Text(L10n.captureHintRear)
                            .font(.caption)
                            .foregroundStyle(Color.white.opacity(0.78))
                    }

                    RecordingSessionPanel(studio: studio)
                    SavedTakesPanel(studio: studio)

                    HStack(spacing: 12) {
                        Button(studio.isRecording ? L10n.buttonRecording : L10n.buttonStartCapture) {
                            studio.beginRecording()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(studio.isRecording)

                        Button(L10n.buttonStop) {
                            studio.stopRecording()
                        }
                        .buttonStyle(.bordered)
                        .disabled(!studio.isRecording)

                        Button(L10n.buttonReplayStage) {
                            studio.enterStageMode()
                        }
                        .buttonStyle(.bordered)
                        .disabled(!studio.hasClip)
                    }
                }
                .padding(18)
                .frame(maxWidth: 440, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(alignment: .topLeading) {
                LinearGradient(
                    colors: [Color.black.opacity(0.78), Color.black.opacity(0.08)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 520)
                .ignoresSafeArea()
            }
        }
        .onAppear {
            studio.prepareCapturePreviewIfNeeded()
        }
    }
}

private struct StageExperienceView: View {
    @ObservedObject var studio: StudioViewModel

    var body: some View {
        ZStack {
            StagePlaybackView(studio: studio)
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    Text(L10n.stageTitle)
                        .font(.headline)
                        .foregroundStyle(.white)

                    Text(studio.statusText)
                        .font(.subheadline)
                        .foregroundStyle(Color.white.opacity(0.9))

                    HStack(spacing: 16) {
                        Label(studio.clipDurationText, systemImage: "music.note")
                        Label(L10n.frames(studio.recordedFrameCount), systemImage: "film")
                    }
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(0.78))

                    Text(L10n.stageDescription)
                        .font(.caption)
                        .foregroundStyle(Color.white.opacity(0.78))

                    StageTakeReviewPanel(studio: studio)

                    VStack(spacing: 12) {
                        Button(studio.isCurrentTakeAccepted ? L10n.buttonTakeConfirmed : L10n.buttonConfirmTake) {
                            studio.confirmCurrentTake()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!studio.canConfirmCurrentTake)
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Button(studio.isPlaying ? L10n.buttonPause : L10n.buttonPlay) {
                            studio.togglePlayback()
                        }
                        .buttonStyle(.bordered)
                        .disabled(!studio.hasClip)
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Button(L10n.buttonRecordAgain) {
                            studio.returnToCapture()
                        }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(18)
                .frame(maxWidth: 440, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(alignment: .topLeading) {
                LinearGradient(
                    colors: [Color.black.opacity(0.82), Color.black.opacity(0.12)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 520)
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

private struct StageTakeReviewPanel: View {
    @ObservedObject var studio: StudioViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.stageReviewTitle)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)

            if let currentTake = studio.currentTake {
                VStack(alignment: .leading, spacing: 10) {
                    Text(L10n.stageCurrentTakeLabel)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.white.opacity(0.82))

                    StageTakeReviewCard(
                        take: currentTake,
                        isCurrent: true,
                        isAccepted: currentTake.isAccepted,
                        onOpen: nil
                    )

                    if let acceptedTake = studio.acceptedTake, acceptedTake.id != currentTake.id {
                        Label("\(L10n.stageAcceptedTakeLabel): \(L10n.takeCardTitle(acceptedTake.takeIndex))", systemImage: "checkmark.seal.fill")
                            .font(.caption)
                            .foregroundStyle(Color.white.opacity(0.72))
                    }
                }
            } else {
                Text(L10n.stageReviewEmpty)
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(0.68))
            }

            if !selectableTakes.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(selectableTakes) { take in
                            StageTakeReviewCard(
                                take: take,
                                isCurrent: studio.currentTake?.id == take.id,
                                isAccepted: take.isAccepted,
                                onOpen: studio.currentTake?.id == take.id ? nil : {
                                    studio.loadTake(take)
                                }
                            )
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var selectableTakes: [MotionTakeSummary] {
        guard let currentTakeID = studio.currentTake?.id else {
            return studio.currentSessionTakes
        }

        return studio.currentSessionTakes.filter { $0.id != currentTakeID }
    }
}

private struct RecordingSessionPanel: View {
    @ObservedObject var studio: StudioViewModel

    private let bpmRange = Array(stride(from: 60, through: 180, by: 5)).map { Int($0) }
    private let barRange = Array(1...4)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.sessionTitle)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)

            Text(studio.recordingSessionSummaryText)
                .font(.caption)
                .foregroundStyle(Color.white.opacity(0.72))

            VStack(spacing: 10) {
                settingRow(title: L10n.sessionBPMTitle) {
                    Picker(L10n.sessionBPMTitle, selection: Binding(
                        get: { Int(studio.recordingContext.bpm.rounded()) },
                        set: { studio.updateBPM(Double($0)) }
                    )) {
                        ForEach(bpmRange, id: \.self) { bpm in
                            Text("\(bpm)").tag(bpm)
                        }
                    }
                    .pickerStyle(.menu)
                }

                settingRow(title: L10n.sessionTimeSignatureTitle) {
                    Picker(L10n.sessionTimeSignatureTitle, selection: Binding(
                        get: { studio.selectedTimeSignature },
                        set: { studio.selectTimeSignature($0) }
                    )) {
                        ForEach(studio.availableTimeSignatures) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 160)
                }

                settingRow(title: L10n.sessionBarsTitle) {
                    Picker(L10n.sessionBarsTitle, selection: Binding(
                        get: { studio.recordingContext.targetBarCount },
                        set: { studio.updateTargetBarCount($0) }
                    )) {
                        ForEach(barRange, id: \.self) { bars in
                            Text("\(bars)").tag(bars)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 160)
                }

                settingRow(title: L10n.sessionCountInTitle) {
                    Picker(L10n.sessionCountInTitle, selection: Binding(
                        get: { studio.recordingContext.countInBarCount },
                        set: { studio.updateCountInBarCount($0) }
                    )) {
                        ForEach(0..<3, id: \.self) { bars in
                            Text("\(bars)").tag(bars)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 160)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func settingRow<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.white.opacity(0.82))

            Spacer(minLength: 12)

            content()
                .labelsHidden()
                .tint(.white)
                .colorScheme(.dark)
        }
    }
}

private struct SavedTakesPanel: View {
    @ObservedObject var studio: StudioViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.savedTakesTitle)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)

            if studio.hasSavedTakes {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(studio.currentSessionTakes) { take in
                            SavedTakeCard(take: take) {
                                studio.loadTake(take)
                            }
                        }
                    }
                }
            } else {
                Text(L10n.emptySavedTakes)
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(0.68))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct SavedTakeCard: View {
    let take: MotionTakeSummary
    let onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.takeCardTitle(take.takeIndex))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)

            Text(take.captureMode.title)
                .font(.caption2)
                .foregroundStyle(Color.white.opacity(0.72))

            Text(L10n.takeCardMeta(formattedDuration, take.frameCount))
                .font(.caption2)
                .foregroundStyle(Color.white.opacity(0.6))

            Button(L10n.buttonOpenTake, action: onOpen)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding(12)
        .frame(width: 150, alignment: .leading)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var formattedDuration: String {
        take.durationSeconds.formatted(.number.precision(.fractionLength(1)))
    }
}

private struct StageTakeReviewCard: View {
    let take: MotionTakeSummary
    let isCurrent: Bool
    let isAccepted: Bool
    let onOpen: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.takeCardTitle(take.takeIndex))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)

                    Text(take.captureMode.title)
                        .font(.caption2)
                        .foregroundStyle(Color.white.opacity(0.72))

                    Text(L10n.takeCardMeta(formattedDuration, take.frameCount))
                        .font(.caption2)
                        .foregroundStyle(Color.white.opacity(0.6))
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 6) {
                    if isCurrent {
                        StageTakeBadge(title: L10n.takeBadgeCurrent, systemImage: "eye.fill")
                    }

                    if isAccepted {
                        StageTakeBadge(title: L10n.takeBadgeAccepted, systemImage: "checkmark.seal.fill")
                    }
                }
            }

            if let onOpen {
                Button(L10n.buttonOpenTake, action: onOpen)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .padding(12)
        .frame(width: 190, alignment: .leading)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var formattedDuration: String {
        take.durationSeconds.formatted(.number.precision(.fractionLength(1)))
    }
}

private struct StageTakeBadge: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.14), in: Capsule())
            .foregroundStyle(.white)
    }
}

private struct MockCapturePreviewView: View {
    var body: some View {
        LinearGradient(
            colors: [Color(red: 0.08, green: 0.1, blue: 0.16), Color.black],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}

private struct MotionCaptureARView: UIViewRepresentable {
    @ObservedObject var studio: StudioViewModel

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
        studio.attachCaptureView(view)
        return view
    }

    func updateUIView(_ uiView: ARView, context: Context) {}
}

private struct FrontCameraCaptureView: UIViewRepresentable {
    @ObservedObject var studio: StudioViewModel

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .black
        studio.attachFrontCaptureView(view)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        studio.updateFrontCapturePreview(in: uiView)
    }
}

private struct StagePlaybackView: UIViewRepresentable {
    @ObservedObject var studio: StudioViewModel

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        studio.attachStageView(view)
        return view
    }

    func updateUIView(_ uiView: ARView, context: Context) {}
}

#Preview {
    ContentView()
}
