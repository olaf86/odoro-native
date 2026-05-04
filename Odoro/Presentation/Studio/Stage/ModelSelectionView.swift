//
//  ModelSelectionView.swift
//  Odoro
//

import SwiftUI
import UniformTypeIdentifiers

struct ModelSelectionView: View {
    @ObservedObject var studio: StudioViewModel
    @State private var isAvatarImportPickerPresented = false

    var body: some View {
        NavigationShell(
            title: "Model Selection",
            subtitle: "Choose how playback is visualized, then return to the stage.",
            trailing: {
                Button {
                    isAvatarImportPickerPresented = true
                } label: {
                    Label("Import GLB", systemImage: "square.and.arrow.down.on.square")
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .disabled(studio.isImportingAvatar)
            },
            onBack: studio.goBack
        ) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    ForEach(studio.availableAvatarOptions) { option in
                        AvatarStyleCard(
                            option: option,
                            isSelected: studio.selectedAvatarOption.selection == option.selection,
                            isInteractionDisabled: studio.isImportingAvatar,
                            onSelect: { studio.selectAvatarOption(option) },
                            onReinstall: option.source == .downloadable ? {
                                studio.reinstallAvatar(option)
                            } : nil
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 52)
            }
        }
        .overlay(alignment: .bottom) {
            SwipeBackEdgeZone(direction: .up) {
                studio.goBack()
            }
        }
        .fileImporter(
            isPresented: $isAvatarImportPickerPresented,
            allowedContentTypes: [UTType(filenameExtension: "glb") ?? .data],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case let .success(urls):
                guard let url = urls.first else { return }
                studio.importAvatar(from: url)
            case let .failure(error):
                studio.showFeatureNotice("Avatar import failed: \(error.localizedDescription)")
            }
        }
    }
}

private struct AvatarStyleCard: View {
    let option: StageAvatarOption
    let isSelected: Bool
    let isInteractionDisabled: Bool
    let onSelect: () -> Void
    let onReinstall: (() -> Void)?

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: 14) {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(LinearGradient(
                        colors: isSelected
                            ? [Color.red.opacity(0.9), Color.orange.opacity(0.9)]
                            : [Color.white.opacity(0.12), Color.white.opacity(0.06)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 92, height: 92)
                    .overlay {
                        Image(systemName: option.systemImageName)
                            .font(.largeTitle)
                            .foregroundStyle(.white)
                    }

                VStack(alignment: .leading, spacing: 8) {
                    Text(option.titleText)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)

                    Text(option.subtitle)
                        .font(.footnote)
                        .foregroundStyle(Color.white.opacity(0.72))

                    HStack(spacing: 8) {
                        Text(statusText)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(isSelected ? Color.orange.opacity(0.9) : Color.white.opacity(0.54))

                        if let badgeText = option.badgeText {
                            Text(badgeText)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Color.white.opacity(0.82))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.white.opacity(0.12), in: Capsule())
                        }
                    }
                }

                VStack(alignment: .trailing, spacing: 6) {
                    if let onReinstall, option.installState == .installed {
                        Button(action: onReinstall) {
                            Image(systemName: "arrow.clockwise")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Color.white.opacity(0.6))
                                .padding(8)
                                .background(Color.white.opacity(0.10), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .disabled(isInteractionDisabled)
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(18)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isInteractionDisabled)
        .opacity(isInteractionDisabled ? 0.7 : 1)
    }

    private var statusText: String {
        if isSelected {
            return "Selected"
        }

        if option.installState == .notInstalled {
            return "Tap to download"
        }

        return "Tap to use this view"
    }
}
