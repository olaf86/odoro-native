//
//  ContentView.swift
//  Visco
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
            } else {
                MotionCaptureARView(studio: studio)
            }

            VStack(alignment: .leading, spacing: 14) {
                Text("Visco Capture")
                    .font(.headline)
                    .foregroundStyle(.white)

                Text(studio.statusText)
                    .font(.subheadline)
                    .foregroundStyle(Color.white.opacity(0.9))

                HStack(spacing: 16) {
                    Label("\(studio.recordedFrameCount) frames", systemImage: "figure.dance")
                    Label(studio.recordingDurationText, systemImage: "clock")
                }
                .font(.caption)
                .foregroundStyle(Color.white.opacity(0.78))

                if studio.usesMockSource {
                    Text("シミュレータ用の MockMotionSource を使っています。疑似ダンスを収録対象として扱います。")
                        .font(.caption)
                        .foregroundStyle(Color.white.opacity(0.78))
                } else {
                    Text("背面カメラで全身を捉え、短い振り付けを収録します。停止するとステージ再生に切り替わります。")
                        .font(.caption)
                        .foregroundStyle(Color.white.opacity(0.78))
                }

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
    @ObservedObject var studio: StudioViewModel

    var body: some View {
        ZStack {
            StagePlaybackView(studio: studio)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 14) {
                Text("Visco Stage")
                    .font(.headline)
                    .foregroundStyle(.white)

                Text(studio.statusText)
                    .font(.subheadline)
                    .foregroundStyle(Color.white.opacity(0.9))

                HStack(spacing: 16) {
                    Label(studio.clipDurationText, systemImage: "music.note")
                    Label("\(studio.recordedFrameCount) frames", systemImage: "film")
                }
                .font(.caption)
                .foregroundStyle(Color.white.opacity(0.78))

                Text("収録した関節位置を簡易ダンサーとしてループ再生しています。将来的にはリグ済みキャラクターへ置き換える前提のモックです。")
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(0.78))

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
                Text("Mock Dance Source")
                    .font(.title3.weight(.semibold))
                Text("カメラの代わりに疑似ダンスクリップを流し、収録から再生までのフローを確認します。")
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
