//
//  MusicSelectionView.swift
//  Odoro
//

import SwiftUI

struct MusicSelectionView: View {
    @ObservedObject var studio: StudioViewModel

    var body: some View {
        NavigationShell(
            title: "Music Source",
            subtitle: "Choose the reference audio shown during capture.",
            onBack: studio.goBack
        ) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    ForEach(studio.availableAudioSources) { option in
                        AudioSourceCard(
                            option: option,
                            isSelected: studio.activeAudioSource.id == option.id,
                            isPreviewAvailable: studio.canPreviewAudioSource(option),
                            isPreviewing: studio.isPreviewingAudioSource(option)
                        ) {
                            studio.selectAudioSource(option)
                        } onPreview: {
                            studio.toggleAudioPreview(for: option)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 32)
            }
        }
        .overlay(alignment: .trailing) {
            SwipeBackEdgeZone(direction: .left) {
                studio.goBack()
            }
        }
    }
}

private struct AudioSourceCard: View {
    let option: AudioSourceOption
    let isSelected: Bool
    let isPreviewAvailable: Bool
    let isPreviewing: Bool
    let onSelect: () -> Void
    let onPreview: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(option.title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)

                    Text(option.subtitle)
                        .font(.footnote)
                        .foregroundStyle(Color.white.opacity(0.72))
                }

                Spacer(minLength: 0)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.red : Color.white.opacity(0.5))
            }

            HStack(spacing: 10) {
                InfoChip(text: option.tempoSourceType == .metronome ? "Metronome" : "Reference Track", systemImage: "music.note")

                if let preferredBPM = option.preferredBPM {
                    InfoChip(text: "\(Int(preferredBPM.rounded())) BPM", systemImage: "metronome")
                }

                if isPreviewAvailable {
                    Button(action: onPreview) {
                        Label(isPreviewing ? "Stop" : "Preview", systemImage: isPreviewing ? "stop.fill" : "play.fill")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(isSelected ? 0.16 : 0.08), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .onTapGesture(perform: onSelect)
    }
}
