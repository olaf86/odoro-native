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
        .simultaneousGesture(stageSwipeGesture)
    }

    private var stageSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 36, coordinateSpace: .local)
            .onEnded { value in
                if value.translation.height > 70 {
                    viewModel.openModelSelection()
                }
            }
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

            VStack(alignment: .leading, spacing: 5) {
                Text(viewModel.currentClipTitle)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)

                Text(viewModel.currentClipSubtitle)
                    .font(.footnote)
                    .foregroundStyle(Color.white.opacity(0.72))
            }

            Spacer(minLength: 0)

            CapturePill(text: viewModel.selectedAvatarTitle, systemImage: "cube.transparent")
        }
        .padding(16)
        .background(Color.black.opacity(0.24), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

private struct StageBottomBar: View {
    @ObservedObject var viewModel: StageViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker(
                "Skeleton Debug",
                selection: Binding(
                    get: { viewModel.stageDebugMotionViewMode },
                    set: viewModel.setStageDebugMotionViewMode
                )
            ) {
                ForEach(viewModel.availableStageDebugMotionViewModes) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Text("Swipe down to pick another model view.")
                .font(.footnote)
                .foregroundStyle(Color.white.opacity(0.72))

            HStack(spacing: 12) {
                Button {
                    viewModel.togglePlayback()
                } label: {
                    Label(viewModel.isPlaying ? "Pause" : "Play", systemImage: viewModel.isPlaying ? "pause.fill" : "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(StageActionButtonStyle(fill: Color.white.opacity(0.16)))
                .disabled(!viewModel.hasClip)

                Button {
                    viewModel.saveCurrentClipToArchive()
                } label: {
                    Label("Save", systemImage: "arrow.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(StageActionButtonStyle(fill: Color.red.opacity(0.88)))
                .disabled(!viewModel.hasClip)
            }

            Button {
                viewModel.returnToCapture()
            } label: {
                Text("Record Again")
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.1), in: Capsule())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
        }
        .padding(18)
        .background(Color.black.opacity(0.34), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }
}
