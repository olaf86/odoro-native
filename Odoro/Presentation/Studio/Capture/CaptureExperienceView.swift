//
//  CaptureExperienceView.swift
//  Odoro
//

import SwiftUI

struct CaptureExperienceView: View {
    private let studio: StudioViewModel
    @StateObject private var viewModel: CaptureViewModel

    init(studio: StudioViewModel) {
        self.studio = studio
        _viewModel = StateObject(wrappedValue: CaptureViewModel(studio: studio))
    }

    var body: some View {
        ZStack {
            capturePreview

            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    viewModel.revealSwipeHints()
                }

            CaptureSwipeHintCluster(isVisible: viewModel.swipeHintsVisible)
                .padding(.horizontal, 28)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .ignoresSafeArea()
        .safeAreaInset(edge: .top, spacing: 0) {
            CaptureHeader(viewModel: viewModel)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            CaptureRecordBar(viewModel: viewModel)
                .padding(.horizontal, 28)
                .padding(.top, 12)
                .padding(.bottom, 20)
        }
        .onAppear {
            viewModel.prepareCapturePreviewIfNeeded()
        }
        .simultaneousGesture(captureSwipeGesture)
    }

    @ViewBuilder
    private var capturePreview: some View {
        if viewModel.usesMockSource {
            MockCapturePreviewView()
        } else if viewModel.usesFrontCameraSource {
            FrontCameraCaptureView(studio: studio)
        } else {
            MotionCaptureARView(studio: studio)
        }
    }

    private var captureSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 36, coordinateSpace: .local)
            .onEnded { value in
                guard !viewModel.isRecording else { return }

                let horizontal = value.translation.width
                let vertical = value.translation.height

                if abs(horizontal) > abs(vertical), horizontal < -60 {
                    viewModel.openClipLibrary()
                } else if abs(horizontal) > abs(vertical), horizontal > 60 {
                    viewModel.openMusicSelection()
                } else if vertical > 70 {
                    viewModel.openSessionSettings()
                }
            }
    }
}

private struct CaptureHeader: View {
    @ObservedObject var viewModel: CaptureViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(viewModel.captureBeatProgressText)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)

                    Text(viewModel.captureBeatSummaryText)
                        .font(.footnote)
                        .foregroundStyle(Color.white.opacity(0.72))
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 8) {
                    CapturePill(text: viewModel.captureModeTitle, systemImage: "camera.metering.center.weighted")
                    CapturePill(text: viewModel.statusText, systemImage: "waveform.path.ecg")
                }
            }

            ProgressView(value: viewModel.captureBeatProgress)
                .progressViewStyle(.linear)
                .tint(viewModel.isRecording ? Color.red : Color.white)

            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.audioSourceTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)

                Text(viewModel.recordingSessionSummaryText)
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(0.72))
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

private struct CaptureRecordBar: View {
    @ObservedObject var viewModel: CaptureViewModel

    var body: some View {
        VStack(spacing: 12) {
            if viewModel.hasClip {
                Button {
                    viewModel.enterStageMode()
                } label: {
                    Label(viewModel.currentClipTitle, systemImage: "play.rectangle.fill")
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.black.opacity(0.46), in: Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
            }

            Button {
                if viewModel.isRecording {
                    viewModel.stopRecording()
                } else {
                    viewModel.beginRecording()
                }
            } label: {
                TikTokRecordButton(isRecording: viewModel.isRecording)
            }
            .buttonStyle(.plain)
        }
    }
}

private struct CaptureSwipeHintCluster: View {
    let isVisible: Bool

    var body: some View {
        ZStack {
            if isVisible {
                VStack(spacing: 14) {
                    SwipeHintCard(
                        title: "Session Settings",
                        subtitle: "Swipe down to adjust BPM, meter, bars, and count-in.",
                        systemImage: "arrow.down"
                    )

                    HStack(spacing: 14) {
                        SwipeHintCard(
                            title: "Clip Library",
                            subtitle: "Swipe left to review captured clips.",
                            systemImage: "arrow.left"
                        )

                        SwipeHintCard(
                            title: "Music Source",
                            subtitle: "Swipe right to choose the track or metronome.",
                            systemImage: "arrow.right"
                        )
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .frame(maxWidth: .infinity, minHeight: 180)
    }
}

private struct SwipeHintCard: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white)

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(Color.white.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.34), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct TikTokRecordButton: View {
    let isRecording: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color.white)
                .frame(width: 88, height: 88)

            if isRecording {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.red)
                    .frame(width: 34, height: 34)
            } else {
                Circle()
                    .fill(Color.red)
                    .frame(width: 62, height: 62)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .strokeBorder(Color.white.opacity(0.5), lineWidth: 3)
                .frame(width: 96, height: 96)
        }
        .shadow(color: Color.black.opacity(0.28), radius: 12, y: 8)
    }
}
