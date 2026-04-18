//
//  ContentView.swift
//  Odoro
//
//  Created by Yuta Ogawa on 2026/04/07.
//

import ARKit
import RealityKit
import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var studio: StudioViewModel

    init(
        archiveStore: MotionArchiveStore? = nil,
        recordingContext: MotionRecordingContext? = nil
    ) {
        _studio = StateObject(
            wrappedValue: StudioViewModel(
                archiveStore: archiveStore,
                recordingContext: recordingContext
            )
        )
    }

    var body: some View {
        ZStack {
            currentScreen
                .id(studio.screen.rawValue)
                .transition(studio.screenTransition.transition)

            if let transientMessage = studio.transientMessage {
                VStack {
                    Spacer()
                    NoticeToast(message: transientMessage) {
                        studio.clearFeatureNotice()
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 28)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.36, dampingFraction: 0.9), value: studio.screen)
        .animation(.spring(response: 0.28, dampingFraction: 0.88), value: studio.transientMessage)
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                studio.prepareCapturePreviewIfNeeded()
            case .inactive, .background:
                studio.suspendStudioForInactivity()
            @unknown default:
                break
            }
        }
    }

    @ViewBuilder
    private var currentScreen: some View {
        switch studio.screen {
        case .capture:
            CaptureExperienceView(studio: studio)
        case .musicSelection:
            MusicSelectionView(studio: studio)
        case .sessionSettings:
            SessionSettingsView(studio: studio)
        case .clipsLibrary:
            ClipLibraryView(studio: studio)
        case .stage:
            StageExperienceView(studio: studio)
        case .modelSelection:
            ModelSelectionView(studio: studio)
        case .archive:
            ArchiveExperienceView(studio: studio)
        }
    }
}

private struct CaptureExperienceView: View {
    @ObservedObject var studio: StudioViewModel

    var body: some View {
        ZStack {
            capturePreview

            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    studio.revealSwipeHints()
                }

            VStack(spacing: 0) {
                CaptureHeader(studio: studio)
                    .padding(.horizontal, 16)
                    .padding(.top, 14)

                Spacer()

                CaptureSwipeHintCluster(isVisible: studio.swipeHintsVisible)
                    .padding(.horizontal, 28)
                    .padding(.bottom, 96)

                CaptureRecordBar(studio: studio)
                    .padding(.horizontal, 28)
                    .padding(.bottom, 28)
            }
        }
        .ignoresSafeArea()
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
                    studio.openMusicSelection()
                } else if abs(horizontal) > abs(vertical), horizontal > 60 {
                    studio.openClipLibrary()
                } else if vertical < -70 {
                    studio.openSessionSettings()
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

            VStack(spacing: 0) {
                StageHeader(studio: studio)
                    .padding(.horizontal, 16)
                    .padding(.top, 14)

                Spacer()

                StageBottomBar(studio: studio)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 26)
            }
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
                if value.translation.height < -70 {
                    studio.openModelSelection()
                }
            }
    }
}

private struct MusicSelectionView: View {
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
                            isSelected: studio.activeAudioSource.id == option.id
                        ) {
                            studio.selectAudioSource(option)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
        }
    }
}

private struct SessionSettingsView: View {
    @ObservedObject var studio: StudioViewModel

    private let bpmRange = Array(stride(from: 60, through: 180, by: 2)).map { Int($0) }
    private let barRange = Array(1...8)

    var body: some View {
        NavigationShell(
            title: "Recording Session",
            subtitle: "Move the setup controls out of capture so the camera stays clean.",
            onBack: studio.goBack
        ) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    SettingsCard(title: "Session Overview", icon: "music.note.list") {
                        Text(studio.recordingSessionSummaryText)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white)
                    }

                    SettingsCard(title: "Capture Mode", icon: "camera.aperture") {
                        Picker(
                            "Capture Mode",
                            selection: Binding(
                                get: { studio.captureMode },
                                set: { studio.selectCaptureMode($0) }
                            )
                        ) {
                            ForEach(studio.availableCaptureModes) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .disabled(studio.isRecording)
                    }

                    SettingsCard(title: "Tempo", icon: "metronome") {
                        Picker(
                            "BPM",
                            selection: Binding(
                                get: { Int(studio.recordingContext.bpm.rounded()) },
                                set: { studio.updateBPM(Double($0)) }
                            )
                        ) {
                            ForEach(bpmRange, id: \.self) { bpm in
                                Text("\(bpm)").tag(bpm)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(height: 110)
                        .clipped()
                    }

                    SettingsCard(title: "Meter", icon: "music.quarternote.3") {
                        Picker(
                            "Meter",
                            selection: Binding(
                                get: { studio.selectedTimeSignature },
                                set: { studio.selectTimeSignature($0) }
                            )
                        ) {
                            ForEach(studio.availableTimeSignatures) { option in
                                Text(option.title).tag(option)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    SettingsCard(title: "Bars", icon: "rectangle.split.3x1") {
                        Picker(
                            "Bars",
                            selection: Binding(
                                get: { studio.recordingContext.targetBarCount },
                                set: { studio.updateTargetBarCount($0) }
                            )
                        ) {
                            ForEach(barRange, id: \.self) { bars in
                                Text("\(bars)").tag(bars)
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    SettingsCard(title: "Count-In", icon: "waveform.badge.plus") {
                        Picker(
                            "Count-In",
                            selection: Binding(
                                get: { studio.recordingContext.countInBarCount },
                                set: { studio.updateCountInBarCount($0) }
                            )
                        ) {
                            ForEach(0..<4, id: \.self) { bars in
                                Text("\(bars)").tag(bars)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 28)
            }
        }
    }
}

private struct ClipLibraryView: View {
    @ObservedObject var studio: StudioViewModel

    var body: some View {
        NavigationShell(
            title: "Clip Library",
            subtitle: "Review past takes and jump straight back into playback.",
            trailing: {
                Button {
                    studio.showFeatureNotice("Video import and motion analysis are next on the list.")
                } label: {
                    Label("Upload", systemImage: "plus.rectangle.on.folder")
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
            },
            onBack: studio.goBack
        ) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    if studio.hasLibraryClips {
                        ForEach(studio.libraryClips) { clip in
                            ClipLibraryCard(
                                clip: clip,
                                onRename: { studio.renameClip(clip, to: $0) },
                                onOpen: { studio.openTakeFromLibrary(clip) }
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
                .padding(.bottom, 30)
            }
        }
    }
}

private struct ModelSelectionView: View {
    @ObservedObject var studio: StudioViewModel

    var body: some View {
        NavigationShell(
            title: "Model Selection",
            subtitle: "Swipe up from playback to switch how the motion is visualized.",
            onBack: studio.goBack
        ) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    ForEach(studio.availableAvatarStyles) { style in
                        AvatarStyleCard(
                            style: style,
                            isSelected: studio.selectedAvatarStyle == style
                        ) {
                            studio.selectAvatarStyle(style)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
        }
    }
}

private struct ArchiveExperienceView: View {
    @ObservedObject var studio: StudioViewModel

    var body: some View {
        NavigationShell(
            title: "Archive",
            subtitle: "This will grow into the sharing and multi-motion composition workspace.",
            onBack: studio.goBack
        ) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    ArchiveHeroCard(studio: studio)

                    PlaceholderPanel(
                        title: "Share-ready layout",
                        message: "Keep this screen as the handoff point for exports, SNS sharing, and combining multiple motions into a single showcase."
                    )

                    PlaceholderPanel(
                        title: "Future expansion",
                        message: "The playback composition and publish flow are intentionally staged here so we can expand without reshaping the capture flow again."
                    )
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
        }
    }
}

private struct NavigationShell<Content: View, Trailing: View>: View {
    let title: String
    let subtitle: String
    let trailing: Trailing
    let onBack: () -> Void
    let content: Content

    init(
        title: String,
        subtitle: String,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() },
        onBack: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
        self.onBack = onBack
        self.content = content()
    }

    var body: some View {
        ZStack {
            AppBackground()

            VStack(spacing: 20) {
                HStack(alignment: .top, spacing: 16) {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left")
                            .font(.headline.weight(.semibold))
                            .frame(width: 42, height: 42)
                            .background(Color.white.opacity(0.12), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(title)
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.white)

                        Text(subtitle)
                            .font(.footnote)
                            .foregroundStyle(Color.white.opacity(0.72))
                    }

                    Spacer(minLength: 0)

                    trailing
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)

                content
            }
        }
        .ignoresSafeArea()
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
                        subtitle: "Swipe up to adjust BPM, meter, bars, and count-in.",
                        systemImage: "arrow.up"
                    )

                    HStack(spacing: 14) {
                        SwipeHintCard(
                            title: "Music Source",
                            subtitle: "Swipe left to choose the track or metronome.",
                            systemImage: "arrow.left"
                        )

                        SwipeHintCard(
                            title: "Clip Library",
                            subtitle: "Swipe right to review captured clips.",
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

            CapturePill(text: studio.selectedAvatarStyle.title, systemImage: "cube.transparent")
        }
        .padding(16)
        .background(Color.black.opacity(0.24), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

private struct StageBottomBar: View {
    @ObservedObject var studio: StudioViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Swipe up to pick another model view.")
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

private struct AudioSourceCard: View {
    let option: AudioSourceOption
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
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
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(isSelected ? 0.16 : 0.08), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct SettingsCard<Content: View>: View {
    let title: String
    let icon: String
    let content: Content

    init(title: String, icon: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)

            content
                .tint(.white)
                .colorScheme(.dark)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
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
        case .mock:
            [Color(red: 0.48, green: 0.22, blue: 0.18), Color(red: 0.17, green: 0.05, blue: 0.08)]
        }
    }
}

private struct AvatarStyleCard: View {
    let style: StageAvatarStyle
    let isSelected: Bool
    let onSelect: () -> Void

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
                        Image(systemName: style == .robot ? "figure.dance" : "figure.stand.line.dotted.figure.stand")
                            .font(.largeTitle)
                            .foregroundStyle(.white)
                    }

                VStack(alignment: .leading, spacing: 8) {
                    Text(style.title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)

                    Text(style.subtitle)
                        .font(.footnote)
                        .foregroundStyle(Color.white.opacity(0.72))

                    Text(isSelected ? "Selected" : "Tap to use this view")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(isSelected ? Color.orange.opacity(0.9) : Color.white.opacity(0.54))
                }

                Spacer(minLength: 0)
            }
            .padding(18)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct ArchiveHeroCard: View {
    @ObservedObject var studio: StudioViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(studio.currentClipTitle)
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)

            Text(studio.currentClipSubtitle)
                .font(.footnote)
                .foregroundStyle(Color.white.opacity(0.72))

            HStack(spacing: 10) {
                InfoChip(text: studio.selectedAvatarStyle.title, systemImage: "cube.transparent")
                InfoChip(text: studio.clipDurationText, systemImage: "timer")

                if studio.isCurrentTakeAccepted {
                    InfoChip(text: "Approved Take", systemImage: "checkmark.seal.fill")
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Color.red.opacity(0.78), Color.orange.opacity(0.48)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 28, style: .continuous)
        )
    }
}

private struct PlaceholderPanel: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)

            Text(message)
                .font(.footnote)
                .foregroundStyle(Color.white.opacity(0.72))
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
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

private struct CapturePill: View {
    let text: String
    let systemImage: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.medium))
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.black.opacity(0.34), in: Capsule())
            .foregroundStyle(.white)
    }
}

private struct InfoChip: View {
    let text: String
    let systemImage: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.1), in: Capsule())
            .foregroundStyle(.white)
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

private struct StageActionButtonStyle: ButtonStyle {
    let fill: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.footnote.weight(.semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(fill.opacity(configuration.isPressed ? 0.78 : 1), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .foregroundStyle(.white)
    }
}

private struct NoticeToast: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .foregroundStyle(.white)

            Text(message)
                .font(.footnote)
                .foregroundStyle(.white)

            Spacer(minLength: 0)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.black.opacity(0.82), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct AppBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.05, green: 0.07, blue: 0.12), Color(red: 0.12, green: 0.07, blue: 0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color.orange.opacity(0.18))
                .frame(width: 240, height: 240)
                .blur(radius: 24)
                .offset(x: 130, y: -220)

            Circle()
                .fill(Color.blue.opacity(0.14))
                .frame(width: 280, height: 280)
                .blur(radius: 32)
                .offset(x: -120, y: 260)
        }
    }
}

private struct MockCapturePreviewView: View {
    var body: some View {
        LinearGradient(
            colors: [Color(red: 0.08, green: 0.1, blue: 0.16), Color.black],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
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

private extension StudioScreenTransition {
    var transition: AnyTransition {
        switch self {
        case .fromLeading:
            .asymmetric(insertion: .move(edge: .leading), removal: .move(edge: .trailing))
        case .fromTrailing:
            .asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading))
        case .fromTop:
            .asymmetric(insertion: .move(edge: .top), removal: .move(edge: .bottom))
        case .fromBottom:
            .asymmetric(insertion: .move(edge: .bottom), removal: .move(edge: .top))
        }
    }
}

private func iconName(for captureMode: CaptureMode) -> String {
    switch captureMode {
    case .rearBody3D:
        "figure.walk.motion"
    case .frontUpperBody:
        "person.crop.rectangle"
    case .mock:
        "sparkles.rectangle.stack"
    }
}

#Preview {
    ContentView()
}
