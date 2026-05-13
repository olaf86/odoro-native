//
//  StudioRootView.swift
//  Odoro
//
//  Created by Yuta Ogawa on 2026/04/07.
//

import SwiftUI

struct StudioRootView: View {
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
            Color.black
                .ignoresSafeArea()

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

#Preview {
    StudioRootView()
}
