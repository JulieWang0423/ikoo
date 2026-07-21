import SwiftUI

/// First-launch walkthrough. Explains the share-sheet workflow (share
/// extensions are invisible until you know they exist) and what kind of
/// posts work, then offers the first permission rung.
struct OnboardingView: View {
    var onDone: () -> Void
    @State private var page = 0

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                pageView(
                    symbol: "mappin.and.ellipse",
                    title: "Saved it?\nDon't miss it.",
                    lines: [
                        "You bookmark amazing places on TikTok and RedNote — then never see them again.",
                        "ikoo puts them on a map and reminds you when you're actually nearby.",
                    ]
                ).tag(0)
                pageView(
                    symbol: "square.and.arrow.up",
                    title: "Share a post,\nget the places",
                    lines: [
                        "In TikTok or RedNote, tap Share → ikoo on any post about a place or event.",
                        "ikoo reads the caption and pins every spot it names — a vlog with five stops becomes five pins, saved in one go.",
                        "Posts that name specific places work best. If a video only shows places without naming them, you can add pins by search.",
                    ]
                ).tag(1)
                pageView(
                    symbol: "bell.badge",
                    title: "The magic part",
                    lines: [
                        "Months later, walking through a city — ikoo notices you're near something you saved and sends one quiet notification.",
                        "That needs notification access now, and \"Always\" location later. At most one alert per spot every three days. Your location never leaves your phone.",
                    ]
                ).tag(2)
            }
            .tabViewStyle(.page)
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            VStack(spacing: 10) {
                if page < 2 {
                    Button {
                        withAnimation { page += 1 }
                    } label: {
                        Text("Continue")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Skip") { onDone() }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Button {
                        NotificationService.requestAuthorization()
                        GeofenceManager.shared.requestWhenInUseAuthorization()
                        onDone()
                    } label: {
                        Text("Enable and start")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Not now") { onDone() }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 24)
        }
    }

    private func pageView(symbol: String, title: String, lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Spacer()
            Image(systemName: symbol)
                .font(.system(size: 52))
                .foregroundStyle(.tint)
            Text(title)
                .font(.largeTitle.weight(.bold))
                .fixedSize(horizontal: false, vertical: true)
            ForEach(lines, id: \.self) { line in
                Text(line)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 28)
    }
}
