//
//  ContentView.swift
//  Odoro
//
//  Created by Yuta Ogawa on 2026/04/07.
//

import ARKit
import RealityKit
import SwiftData
import SwiftUI

struct ContentView: View {
    @StateObject private var studio = StudioViewModel()

    var body: some View {
        switch studio.presentation {
        case .capture:
            CaptureExperienceView(studio: studio)
        case .stage:
            StageExperienceView(studio: studio)
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

            VStack(alignment: .leading, spacing: 14) {
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
        .onAppear {
            studio.resumeCaptureSource()
        }
    }
}

private struct StageExperienceView: View {
    @ObservedObject var studio: StudioViewModel

    var body: some View {
        ZStack {
            StagePlaybackView(studio: studio)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 14) {
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

                HStack(spacing: 12) {
                    Button(studio.isPlaying ? L10n.buttonPause : L10n.buttonPlay) {
                        studio.togglePlayback()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!studio.hasClip)

                    Button(L10n.buttonRecordAgain) {
                        studio.returnToCapture()
                    }
                    .buttonStyle(.bordered)

                    Button(L10n.buttonResetClip) {
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

private struct MockCapturePreviewView: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.08, green: 0.1, blue: 0.16), Color.black],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: "figure.dance")
                    .font(.system(size: 72))
                Text(L10n.mockDanceTitle)
                    .font(.title3.weight(.semibold))
                Text(L10n.mockDanceDescription)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.white.opacity(0.8))
                    .padding(.horizontal, 36)
            }
            .foregroundStyle(.white)
        }
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
        .modelContainer(for: Item.self, inMemory: true)
}
