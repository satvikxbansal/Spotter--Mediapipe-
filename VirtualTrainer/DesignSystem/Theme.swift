import SwiftUI

// ────────────────────────────────────────────────────────────────────
// MARK: - Theme
// ────────────────────────────────────────────────────────────────────

/// The visual identity of Virtual Trainer.
///
/// "No-Fluff Noir" — a brutalist dark palette with a single warm accent.
/// Every color, font, spacing token, and motion curve lives here.
/// Nothing is hardcoded in views. Period.
enum Theme {

    // ────────────────────────────────────────────────────────────────
    // MARK: Colors
    // ────────────────────────────────────────────────────────────────

    enum Colors {

        // Surfaces
        /// Near-black. Not pure black — the 5% white gives OLED screens
        /// a hint of materiality so UI elements don't float in a void.
        static let background = Color(white: 0.05)

        /// Card / sheet surface. Separated from background by ~7% brightness.
        static let surface = Color(white: 0.12)

        /// Nested surface (inputs sitting on a card, for example).
        static let surfaceRaised = Color(white: 0.17)

        // Text hierarchy
        /// Bone white. Warm enough to avoid the clinical feel of pure white,
        /// cool enough to avoid yellowing.
        static let textPrimary = Color(white: 0.95)

        /// Muted label text. Quiet but WCAG-legible against surface.
        static let textSecondary = Color(white: 0.52)

        /// Footnotes, timestamps, disabled states.
        static let textTertiary = Color(white: 0.32)

        // Accent
        /// Warm Amber — the only chromatic color in the palette.
        /// Trophy gold, forge glow, earned warmth. Not "health app green."
        static let accent = Color(red: 1.0, green: 0.69, blue: 0.0)

        /// 20% opacity accent for subtle borders, selection highlights, glows.
        static let accentMuted = Color(red: 1.0, green: 0.69, blue: 0.0)
            .opacity(0.20)

        // Semantic
        /// Destructive / error / form-correction red.
        static let danger = Color(red: 1.0, green: 0.30, blue: 0.26)

        /// Positive confirmation (secondary to accent — used sparingly).
        static let positive = Color(red: 0.20, green: 0.84, blue: 0.48)

        // Utility
        /// Hairline dividers between list rows.
        static let divider = Color(white: 0.18)

        /// Full-screen overlay tint (e.g., behind sheets/modals).
        static let scrim = Color.black.opacity(0.65)
    }

    // ────────────────────────────────────────────────────────────────
    // MARK: Spacing (8pt grid)
    // ────────────────────────────────────────────────────────────────

    enum Spacing {
        static let xxxs: CGFloat = 2
        static let xxs: CGFloat  = 4
        static let xs: CGFloat   = 8
        static let sm: CGFloat   = 12
        static let md: CGFloat   = 16
        static let lg: CGFloat   = 24
        static let xl: CGFloat   = 32
        static let xxl: CGFloat  = 48
        static let xxxl: CGFloat = 64
    }

    // ────────────────────────────────────────────────────────────────
    // MARK: Corner Radius
    // ────────────────────────────────────────────────────────────────

    enum Radius {
        static let xs: CGFloat   = 4
        static let sm: CGFloat   = 8
        static let md: CGFloat   = 14
        static let lg: CGFloat   = 20
        static let pill: CGFloat = 999
    }

    // ────────────────────────────────────────────────────────────────
    // MARK: Motion
    // ────────────────────────────────────────────────────────────────

    enum Motion {
        static let snappy: Animation  = .snappy(duration: 0.22)
        static let smooth: Animation  = .easeInOut(duration: 0.35)
        static let spring: Animation  = .interpolatingSpring(stiffness: 280, damping: 20)
        static let bounce: Animation  = .spring(response: 0.4, dampingFraction: 0.6)
    }
}

// ────────────────────────────────────────────────────────────────────
// MARK: - Typography · View Modifiers
// ────────────────────────────────────────────────────────────────────

/// Massive rep counter. SF Rounded, maximum weight, tabular digits.
/// The `.monospacedDigit()` prevents layout jitter when "9" becomes "10".
/// `.numericText()` content transition gives smooth digit-roll animation.
struct RepCounterStyle: ViewModifier {
    var size: CGFloat

    func body(content: Content) -> some View {
        content
            .font(
                .system(size: size, weight: .black, design: .rounded)
                .monospacedDigit()
            )
            .foregroundStyle(Theme.Colors.textPrimary)
            .contentTransition(.numericText())
    }
}

/// Primary section header.
/// Uppercase, heavy weight, negative tracking for that dense brutalist feel.
struct HeaderStyle: ViewModifier {
    var size: CGFloat

    func body(content: Content) -> some View {
        content
            .font(.system(size: size, weight: .heavy))
            .tracking(-0.6)
            .textCase(.uppercase)
            .foregroundStyle(Theme.Colors.textPrimary)
    }
}

/// Secondary header — bold, muted, sentence-case.
struct SubheaderStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(Theme.Colors.textSecondary)
    }
}

/// Body copy. Comfortable reading size, medium weight.
struct BodyStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(Theme.Colors.textPrimary)
    }
}

/// Small metadata / caption text.
struct CaptionStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Theme.Colors.textTertiary)
    }
}

// ────────────────────────────────────────────────────────────────────
// MARK: - Typography · View Extension
// ────────────────────────────────────────────────────────────────────

extension View {
    func repCounter(size: CGFloat = 80) -> some View {
        modifier(RepCounterStyle(size: size))
    }

    func header(size: CGFloat = 28) -> some View {
        modifier(HeaderStyle(size: size))
    }

    func subheader() -> some View {
        modifier(SubheaderStyle())
    }

    func bodyText() -> some View {
        modifier(BodyStyle())
    }

    func caption() -> some View {
        modifier(CaptionStyle())
    }
}

// ────────────────────────────────────────────────────────────────────
// MARK: - Button Styles
// ────────────────────────────────────────────────────────────────────

/// Primary CTA: full-width, 56pt tall, accent fill, bold uppercase label.
struct PrimaryCTAStyle: ButtonStyle {
    var destructive: Bool = false

    private var fill: Color {
        destructive ? Theme.Colors.danger : Theme.Colors.accent
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .bold))
            .tracking(0.4)
            .textCase(.uppercase)
            .foregroundStyle(Theme.Colors.background)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(fill)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
            .opacity(configuration.isPressed ? 0.78 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(Theme.Motion.snappy, value: configuration.isPressed)
    }
}

/// Secondary / ghost CTA: outline only, accent stroke, transparent fill.
struct SecondaryCTAStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .bold))
            .tracking(0.3)
            .textCase(.uppercase)
            .foregroundStyle(Theme.Colors.accent)
            .frame(maxWidth: .infinity, minHeight: 50)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.md)
                    .stroke(Theme.Colors.accent, lineWidth: 1.5)
            )
            .opacity(configuration.isPressed ? 0.55 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(Theme.Motion.snappy, value: configuration.isPressed)
    }
}
