//
//  ArchiveExperienceView.swift
//  Odoro
//

import SwiftUI

struct ArchiveExperienceView: View {
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
                .padding(.top, 4)
                .padding(.bottom, 30)
            }
        }
        .overlay(alignment: .trailing) {
            SwipeBackEdgeZone(direction: .left) {
                studio.goBack()
            }
        }
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
                InfoChip(text: studio.selectedAvatarOption.titleText, systemImage: "cube.transparent")
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
