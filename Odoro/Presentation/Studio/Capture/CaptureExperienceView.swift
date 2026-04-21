//
//  CaptureExperienceView.swift
//  Odoro
//

import SwiftUI

struct CaptureExperienceView: View {
    @ObservedObject var studio: StudioViewModel

    var body: some View {
        ZStack {
            capturePreview

            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    studio.revealSwipeHints()
                }

            CaptureSwipeHintCluster(isVisible: studio.swipeHintsVisible)
                .padding(.horizontal, 28)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .ignoresSafeArea()
        .safeAreaInset(edge: .top, spacing: 0) {
            CaptureHeader(studio: studio)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            CaptureRecordBar(studio: studio)
                .padding(.horizontal, 28)
                .padding(.top, 12)
                .padding(.bottom, 20)
        }
        .onAppear {
            studio.prepareCapturePreviewIfNeeded()
        }
        .simultaneousGesture(captureSwipeGesture)
    }

    @ViewBuilder
    private var capturePreview: some View {
        if studio.usesMockSource {
            MockCapturePreviewView()
        } else if studio.usesFrontCameraSource {
            FrontCameraCaptureView(studio: studio)
        } else {
            MotionCaptureARView(studio: studio)
        }
    }

    private var captureSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 36, coordinateSpace: .local)
            .onEnded { value in
                guard !studio.isRecording else { return }

                let horizontal = value.translation.width
                let vertical = value.translation.height

                if abs(horizontal) > abs(vertical), horizontal < -60 {
                    studio.openClipLibrary()
                } else if abs(horizontal) > abs(vertical), horizontal > 60 {
                    studio.openMusicSelection()
                } else if vertical > 70 {
                    studio.openSessionSettings()
                }
            }
    }
}

private struct CaptureHeader: View {
    @ObservedObject var studio: StudioViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(studio.captureBeatProgressText)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)

                    Text(studio.captureBeatSummaryText)
                        .font(.footnote)
                        .foregroundStyle(Color.white.opacity(0.72))
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 8) {
                    CapturePill(text: studio.captureMode.title, systemImage: "camera.metering.center.weighted")
                    CapturePill(text: studio.statusText, systemImage: "waveform.path.ecg")
                }
            }

            ProgressView(value: studio.captureBeatProgress)
                .progressViewStyle(.linear)
                .tint(studio.isRecording ? Color.red : Color.white)

            VStack(alignment: .leading, spacing: 4) {
                Text(studio.audioSourceTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)

                Text(studio.recordingSessionSummaryText)
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(0.72))
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

private struct CaptureRecordBar: View {
    @ObservedObject var studio: StudioViewModel

    var body: some View {
        VStack(spacing: 12) {
            if studio.hasClip {
                Button {
                    studio.enterStageMode()
                } label: {
                    Label(studio.currentClipTitle, systemImage: "play.rectangle.fill")
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.black.opacity(0.46), in: Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
            }

            Button {
                if studio.isRecording {
                    studio.stopRecording()
                } else {
                    studio.beginRecording()
                }
            } label: {
                TikTokRecordButton(isRecording: studio.isRecording)
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
