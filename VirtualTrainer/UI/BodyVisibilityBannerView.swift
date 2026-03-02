import SwiftUI

// ────────────────────────────────────────────────────────────────────
// MARK: - BodyVisibilityBannerView
// ────────────────────────────────────────────────────────────────────

/// A compact warning banner that slides in from the top when the
/// camera can't see enough of the user's body to track the exercise.
///
/// Designed to feel urgent but not aggressive — amber tint, SF Symbol
/// icon, concise copy. Slides out automatically once all required
/// joints become visible.
struct BodyVisibilityBannerView: View {

    let message: String
    let visibility: Double

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            iconView
            textStack
            Spacer(minLength: 0)
            visibilityRing
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(bannerBackground)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .stroke(Theme.Colors.accent.opacity(0.25), lineWidth: 1)
        )
        .padding(.horizontal, Theme.Spacing.lg)
        .shadow(color: .black.opacity(0.5), radius: 12, y: 4)
        .allowsHitTesting(false)
    }

    // MARK: - Sub-views

    private var iconView: some View {
        Image(systemName: "figure.walk.motion")
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(Theme.Colors.accent)
            .symbolEffect(.pulse, options: .repeating)
    }

    private var textStack: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxxs) {
            Text("ADJUST POSITION")
                .font(.system(size: 11, weight: .heavy))
                .tracking(1.0)
                .foregroundStyle(Theme.Colors.accent)

            Text(message)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// A tiny ring that fills as more joints become visible,
    /// giving the user real-time spatial feedback.
    private var visibilityRing: some View {
        ZStack {
            Circle()
                .stroke(Theme.Colors.surface, lineWidth: 3)

            Circle()
                .trim(from: 0, to: visibility)
                .stroke(
                    Theme.Colors.accent,
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            Text("\(Int(visibility * 100))")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .frame(width: 32, height: 32)
    }

    private var bannerBackground: some View {
        Theme.Colors.background
            .opacity(0.88)
    }
}

// ────────────────────────────────────────────────────────────────────
// MARK: - Preview
// ────────────────────────────────────────────────────────────────────

#Preview("Visibility Banner — Partial") {
    ZStack {
        Color.black.ignoresSafeArea()

        VStack {
            BodyVisibilityBannerView(
                message: "Move back so your full body — hips, knees, and ankles are visible",
                visibility: 0.6
            )

            Spacer()
        }
        .padding(.top, 80)
    }
}

#Preview("Visibility Banner — No body") {
    ZStack {
        Color.black.ignoresSafeArea()

        VStack {
            BodyVisibilityBannerView(
                message: "Step into the frame so the camera can see you",
                visibility: 0.0
            )

            Spacer()
        }
        .padding(.top, 80)
    }
}
