//
//  StageExperienceView.swift
//  Odoro
//

import SwiftUI

struct StageExperienceView: View {
    @ObservedObject var studio: StudioViewModel

    var body: some View {
        ZStack {
            StagePlaybackView(studio: studio)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            StageHeader(studio: studio)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            StageBottomBar(studio: studio)
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 18)
        }
        .onAppear {
            studio.prepareStagePlayback()
        }
        .onDisappear {
            studio.pausePlayback()
        }
        .simultaneousGesture(stageSwipeGesture)
    }

    private var stageSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 36, coordinateSpace: .local)
            .onEnded { value in
                if value.translation.height > 70 {
                    studio.openModelSelection()
                }
            }
    }
}

private struct StageHeader: View {
    @ObservedObject var studio: StudioViewModel

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: studio.goBack) {
                Image(systemName: "chevron.left")
                    .font(.headline.weight(.semibold))
                    .frame(width: 42, height: 42)
                    .background(Color.black.opacity(0.35), in: Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 5) {
                Text(studio.currentClipTitle)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)

                Text(studio.currentClipSubtitle)
                    .font(.footnote)
                    .foregroundStyle(Color.white.opacity(0.72))
            }

            Spacer(minLength: 0)

            CapturePill(text: studio.selectedAvatarOption.titleText, systemImage: "cube.transparent")
        }
        .padding(16)
        .background(Color.black.opacity(0.24), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

private struct StageBottomBar: View {
    @ObservedObject var studio: StudioViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Swipe down to pick another model view.")
                .font(.footnote)
                .foregroundStyle(Color.white.opacity(0.72))

            HStack(spacing: 12) {
                Button {
                    studio.togglePlayback()
                } label: {
                    Label(studio.isPlaying ? "Pause" : "Play", systemImage: studio.isPlaying ? "pause.fill" : "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(StageActionButtonStyle(fill: Color.white.opacity(0.16)))
                .disabled(!studio.hasClip)

                Button {
                    studio.saveCurrentClipToArchive()
                } label: {
                    Label("Save", systemImage: "arrow.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(StageActionButtonStyle(fill: Color.red.opacity(0.88)))
                .disabled(!studio.hasClip)
            }

            Button {
                studio.returnToCapture()
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
