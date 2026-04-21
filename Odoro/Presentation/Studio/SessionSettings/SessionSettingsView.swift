//
//  SessionSettingsView.swift
//  Odoro
//

import SwiftUI

struct SessionSettingsView: View {
    @StateObject private var viewModel: SessionSettingsViewModel

    private let bpmRange = Array(stride(from: 60, through: 180, by: 2)).map { Int($0) }

    init(studio: StudioViewModel) {
        _viewModel = StateObject(wrappedValue: SessionSettingsViewModel(studio: studio))
    }

    var body: some View {
        NavigationShell(
            title: "Recording Session",
            subtitle: "Move the setup controls out of capture so the camera stays clean.",
            onBack: viewModel.goBack
        ) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    SettingsCard(title: "Session Overview", icon: "music.note.list") {
                        Text(viewModel.recordingSessionSummaryText)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white)
                    }

                    SettingsCard(title: "Capture Mode", icon: "camera.aperture") {
                        Picker(
                            "Capture Mode",
                            selection: Binding(
                                get: { viewModel.captureMode },
                                set: { viewModel.selectCaptureMode($0) }
                            )
                        ) {
                            ForEach(viewModel.availableCaptureModes) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .disabled(viewModel.isRecording)
                    }

                    SettingsCard(title: "Tempo", icon: "metronome") {
                        Picker(
                            "BPM",
                            selection: Binding(
                                get: { viewModel.bpm },
                                set: { viewModel.updateBPM($0) }
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
                                get: { viewModel.selectedTimeSignature },
                                set: { viewModel.selectTimeSignature($0) }
                            )
                        ) {
                            ForEach(viewModel.availableTimeSignatures) { option in
                                Text(option.title).tag(option)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    SettingsCard(title: "Bars", icon: "rectangle.split.3x1") {
                        HStack {
                            Text(viewModel.fixedRecordingBarCountText)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)

                            Spacer()

                            Text("Capture completes automatically.")
                                .font(.caption)
                                .foregroundStyle(Color.white.opacity(0.64))
                        }
                    }

                    SettingsCard(title: "Count-In", icon: "waveform.badge.plus") {
                        Picker(
                            "Count-In",
                            selection: Binding(
                                get: { viewModel.countInBarCount },
                                set: { viewModel.updateCountInBarCount($0) }
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
                .padding(.top, 4)
                .padding(.bottom, 56)
            }
        }
        .overlay(alignment: .bottom) {
            SwipeBackEdgeZone(direction: .up) {
                viewModel.goBack()
            }
        }
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
