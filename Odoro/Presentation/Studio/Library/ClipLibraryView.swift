//
//  ClipLibraryView.swift
//  Odoro
//

import SwiftUI
import UniformTypeIdentifiers

struct ClipLibraryView: View {
    @StateObject private var viewModel: ClipLibraryViewModel
    @State private var isImportPickerPresented = false

    init(studio: StudioViewModel) {
        _viewModel = StateObject(wrappedValue: ClipLibraryViewModel(studio: studio))
    }

    var body: some View {
        NavigationShell(
            title: "Clip Library",
            subtitle: "Review past takes and jump straight back into playback.",
            trailing: {
                Button {
                    isImportPickerPresented = true
                } label: {
                    Label(L10n.buttonImportVideo, systemImage: "plus.rectangle.on.folder")
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .disabled(!viewModel.canImportVideo)
            },
            onBack: viewModel.goBack
        ) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    if viewModel.hasLibraryClips {
                        ForEach(viewModel.libraryClips) { clip in
                            ClipLibraryCard(
                                clip: clip,
                                onRename: { viewModel.renameClip(clip, to: $0) },
                                onOpen: { viewModel.openTakeFromLibrary(clip) }
                            )
                        }
                    } else {
                        PlaceholderPanel(
                            title: "No clips yet",
                            message: "Captured takes will collect here with names, dates, timing info, and source details."
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 30)
            }
        }
        .overlay(alignment: .leading) {
            SwipeBackEdgeZone(direction: .right) {
                viewModel.goBack()
            }
        }
        .fileImporter(
            isPresented: $isImportPickerPresented,
            allowedContentTypes: [.movie, .mpeg4Movie, .quickTimeMovie],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case let .success(urls):
                guard let url = urls.first else { return }
                Task {
                    await viewModel.importVideo(from: url)
                }
            case let .failure(error):
                viewModel.reportVideoImportFailure(error)
            }
        }
    }
}

private struct ClipLibraryCard: View {
    let clip: MotionTakeSummary
    let onRename: (String) -> Void
    let onOpen: () -> Void

    @State private var draftName: String

    init(
        clip: MotionTakeSummary,
        onRename: @escaping (String) -> Void,
        onOpen: @escaping () -> Void
    ) {
        self.clip = clip
        self.onRename = onRename
        self.onOpen = onOpen
        _draftName = State(initialValue: clip.clipName ?? "Clip \(clip.takeIndex)")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                ClipThumbnail(clip: clip)

                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        TextField("Clip name", text: $draftName)
                            .textFieldStyle(.plain)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.white)
                            .submitLabel(.done)
                            .onSubmit(commitRename)

                        Button(action: commitRename) {
                            Image(systemName: "checkmark")
                                .font(.footnote.weight(.bold))
                                .frame(width: 28, height: 28)
                                .background(Color.white.opacity(0.12), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.white)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        LibraryMetaRow(label: "Recorded", value: clip.createdAt.formatted(date: .abbreviated, time: .shortened))
                        LibraryMetaRow(label: "Timing", value: "\(Int(clip.bpm.rounded())) BPM • \(clip.timeSignatureNumerator)/\(clip.timeSignatureDenominator)")
                        LibraryMetaRow(label: "Beats", value: "\(Int(clip.beatLength.rounded())) beats captured")
                        LibraryMetaRow(label: "Source", value: clip.audioAssetReference ?? "Metronome")
                    }
                }
            }

            HStack(spacing: 10) {
                if clip.isAccepted {
                    InfoChip(text: "Accepted", systemImage: "checkmark.seal.fill")
                }

                InfoChip(text: clip.captureMode.title, systemImage: iconName(for: clip.captureMode))
                InfoChip(text: "\(clip.frameCount) frames", systemImage: "film.stack")
            }

            Button(action: onOpen) {
                Label("Open Playback", systemImage: "arrow.right")
                    .font(.footnote.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(StageActionButtonStyle(fill: Color.red.opacity(0.82)))
        }
        .padding(18)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .onChange(of: clip.clipName) { _, newValue in
            draftName = newValue ?? "Clip \(clip.takeIndex)"
        }
    }

    private func commitRename() {
        onRename(draftName)
    }
}

private struct LibraryMetaRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.white.opacity(0.52))
                .frame(width: 56, alignment: .leading)

            Text(value)
                .font(.caption)
                .foregroundStyle(Color.white.opacity(0.8))
        }
    }
}

private struct ClipThumbnail: View {
    let clip: MotionTakeSummary

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: thumbnailColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: iconName(for: clip.captureMode))
                    .font(.title2.weight(.semibold))

                Spacer()

                Text("Take \(clip.takeIndex)")
                    .font(.caption.weight(.semibold))

                Text(clip.durationSeconds.formatted(.number.precision(.fractionLength(1))) + "s")
                    .font(.caption2)
                    .foregroundStyle(Color.white.opacity(0.72))
            }
            .foregroundStyle(.white)
            .padding(14)
        }
        .frame(width: 108, height: 132)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var thumbnailColors: [Color] {
        switch clip.captureMode {
        case .rearBody3D:
            [Color(red: 0.16, green: 0.32, blue: 0.58), Color(red: 0.04, green: 0.08, blue: 0.18)]
        case .frontUpperBody:
            [Color(red: 0.24, green: 0.42, blue: 0.28), Color(red: 0.07, green: 0.12, blue: 0.08)]
        case .importedVideo:
            [Color(red: 0.45, green: 0.30, blue: 0.10), Color(red: 0.16, green: 0.10, blue: 0.04)]
        case .mock:
            [Color(red: 0.48, green: 0.22, blue: 0.18), Color(red: 0.17, green: 0.05, blue: 0.08)]
        }
    }
}
