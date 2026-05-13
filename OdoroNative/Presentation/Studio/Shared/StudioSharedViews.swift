//
//  StudioSharedViews.swift
//  Odoro
//

import SwiftUI

struct NavigationShell<Content: View, Trailing: View>: View {
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
                .ignoresSafeArea()

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
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .safeAreaPadding(.top, 14)
            .safeAreaPadding(.bottom, 8)
        }
    }
}

struct PlaceholderPanel: View {
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

struct CapturePill: View {
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

struct InfoChip: View {
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

struct StageActionButtonStyle: ButtonStyle {
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

struct NoticeToast: View {
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

func iconName(for captureMode: CaptureMode) -> String {
    switch captureMode {
    case .rearBody3D:
        "figure.walk.motion"
    case .frontUpperBody:
        "person.crop.rectangle"
    case .importedVideo:
        "film.stack"
    case .mock:
        "sparkles.rectangle.stack"
    }
}
