//
//  ArchiveExperienceView.swift
//  Odoro
//

import SwiftUI

struct ArchiveExperienceView: View {
    @StateObject private var viewModel: ArchiveViewModel

    init(studio: StudioViewModel) {
        _viewModel = StateObject(wrappedValue: ArchiveViewModel(studio: studio))
    }

    var body: some View {
        NavigationShell(
            title: "Archive",
            subtitle: "This will grow into the sharing and multi-motion composition workspace.",
            onBack: viewModel.goBack
        ) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    ArchiveHeroCard(viewModel: viewModel)

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
                viewModel.goBack()
            }
        }
    }
}

private struct ArchiveHeroCard: View {
    @ObservedObject var viewModel: ArchiveViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(viewModel.currentClipTitle)
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)

            Text(viewModel.currentClipSubtitle)
                .font(.footnote)
                .foregroundStyle(Color.white.opacity(0.72))

            HStack(spacing: 10) {
                InfoChip(text: viewModel.selectedAvatarTitle, systemImage: "cube.transparent")
                InfoChip(text: viewModel.clipDurationText, systemImage: "timer")

                if viewModel.isCurrentTakeAccepted {
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
