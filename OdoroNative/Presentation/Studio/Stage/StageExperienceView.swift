//
//  StageExperienceView.swift
//  Odoro
//

import SwiftUI

struct StageExperienceView: View {
    private let studio: StudioViewModel
    @StateObject private var viewModel: StageViewModel

    init(studio: StudioViewModel) {
        self.studio = studio
        _viewModel = StateObject(wrappedValue: StageViewModel(studio: studio))
    }

    var body: some View {
        ZStack {
            StagePlaybackView(studio: studio)
                .ignoresSafeArea()

            if viewModel.isPreparingPlayback {
                preparingOverlay
            }

            VStack(spacing: 0) {
                Spacer()
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            StageHeader(viewModel: viewModel)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            StageBottomBar(viewModel: viewModel)
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 18)
        }
        .onAppear {
            viewModel.prepareStagePlayback()
        }
        .onDisappear {
            viewModel.pausePlayback()
        }
    }

    private var preparingOverlay: some View {
        ProgressView()
            .progressViewStyle(.circular)
            .tint(.white)
            .scaleEffect(1.4)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.opacity(0.45))
            .ignoresSafeArea()
    }
}

private struct StageHeader: View {
    @ObservedObject var viewModel: StageViewModel

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: viewModel.goBack) {
                Image(systemName: "chevron.left")
                    .font(.headline.weight(.semibold))
                    .frame(width: 42, height: 42)
                    .background(Color.black.opacity(0.35), in: Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.currentClipTitle)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(viewModel.currentClipSubtitle)
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(0.72))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Button(action: viewModel.openModelSelection) {
                CapturePill(text: viewModel.selectedAvatarTitle, systemImage: "cube.transparent")
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

private struct StageBottomBar: View {
    @ObservedObject var viewModel: StageViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if viewModel.availableDebugMotionViewModes.count > 1 {
                debugModePicker
            }

            HStack(spacing: 10) {
                Button {
                    viewModel.openModelSelection()
                } label: {
                    Label("Model", systemImage: "cube.transparent")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(StageActionButtonStyle(fill: Color.white.opacity(0.12)))

                Button {
                    viewModel.returnToCapture()
                } label: {
                    Label("Record Again", systemImage: "camera")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(StageActionButtonStyle(fill: Color.white.opacity(0.12)))
            }

            HStack(spacing: 12) {
                Button {
                    viewModel.togglePlayback()
                } label: {
                    Label(viewModel.isPlaying ? "Pause" : "Play", systemImage: viewModel.isPlaying ? "pause.fill" : "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(StageActionButtonStyle(fill: Color.white.opacity(0.16)))
                .disabled(!viewModel.hasClip || viewModel.isPreparingPlayback)

                Button {
                    viewModel.saveCurrentClipToArchive()
                } label: {
                    Label("Save", systemImage: "arrow.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(StageActionButtonStyle(fill: Color.red.opacity(0.88)))
                .disabled(!viewModel.hasClip || viewModel.isPreparingPlayback)
            }
        }
        .padding(18)
        .background(Color.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private var debugModePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("Debug View")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.66))

                Spacer(minLength: 0)

                Button {
                    viewModel.resetDebugCamera()
                } label: {
                    Label("Reset Camera", systemImage: "view.3d")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Color.white.opacity(0.1), in: Capsule())
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(viewModel.availableDebugMotionViewModes) { mode in
                        Button {
                            viewModel.setDebugMotionViewMode(mode)
                        } label: {
                            Text(mode.title)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(debugModeFill(for: mode), in: Capsule())
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Text("Drag to orbit • Pinch to zoom • Double-tap to reset")
                .font(.caption2)
                .foregroundStyle(Color.white.opacity(0.54))
        }
    }

    private func debugModeFill(for mode: StageDebugMotionViewMode) -> Color {
        if viewModel.selectedDebugMotionViewMode == mode {
            return Color.orange.opacity(0.88)
        }

        return Color.white.opacity(0.12)
    }
}
