import SwiftUI

// ────────────────────────────────────────────────────────────────────
// MARK: - Liquid Glass · Compatibility Layer
// ────────────────────────────────────────────────────────────────────
//
// iOS 26 introduced `.glassEffect()` — a system-level translucent
// material with real-time lensing, specular highlights, and touch
// reactivity. We want to use it everywhere: cards, sheets, popups,
// toolbars, overlays.
//
// Problem: we still target iOS 17+.
//
// Solution: a set of View modifiers that resolve at runtime:
//   - iOS 26+  →  native `.glassEffect()`
//   - iOS <26  →  our dark-surface fallback (Theme.Colors.surface)
//
// Call sites stay clean — no `#available` noise in feature views.
// ────────────────────────────────────────────────────────────────────

// MARK: - Glass Card

/// Applies Liquid Glass to a card-style container.
///
/// ```swift
/// VStack { ... }
///     .glassCard()
/// ```
///
/// On iOS 26+ this is real glass. On earlier versions it falls back
/// to the `surface` color with our standard corner radius.
struct GlassCardModifier: ViewModifier {
    var cornerRadius: CGFloat

    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content
                .padding(Theme.Spacing.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassEffect(.regular.tint(Theme.Colors.accent.opacity(0.08)),
                             in: .rect(cornerRadius: cornerRadius))
        } else {
            content
                .padding(Theme.Spacing.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.Colors.surface)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        }
    }
}

// MARK: - Glass Surface

/// Lightweight glass background — no padding, no frame.
/// Use when you need just the material behind a custom layout.
struct GlassSurfaceModifier: ViewModifier {
    var cornerRadius: CGFloat

    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content
                .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            content
                .background(Theme.Colors.surface)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        }
    }
}

// MARK: - Glass Popup / Sheet Content

/// Full-surface glass for modal content (sheets, popovers, alerts).
/// Uses `.clear` glass variant on iOS 26 for maximum transparency
/// so the underlying workout view bleeds through.
struct GlassPopupModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content
                .padding(Theme.Spacing.lg)
                .frame(maxWidth: .infinity)
                .glassEffect(.regular.tint(Theme.Colors.accent.opacity(0.06)),
                             in: .rect(cornerRadius: Theme.Radius.lg))
        } else {
            content
                .padding(Theme.Spacing.lg)
                .frame(maxWidth: .infinity)
                .background(Theme.Colors.surfaceRaised)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg))
        }
    }
}

// MARK: - Interactive Glass (Buttons / Tappables)

/// Glass treatment for interactive elements that should respond to
/// touch with the native Liquid Glass shimmer on iOS 26.
struct GlassInteractiveModifier: ViewModifier {
    var cornerRadius: CGFloat

    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
        } else {
            content
                .background(Theme.Colors.surfaceRaised)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        }
    }
}

// MARK: - Glass Button Style

/// A ButtonStyle that uses native `.glass` on iOS 26 and falls back
/// to our `PrimaryCTAStyle` on earlier versions.
///
/// ```swift
/// Button("Start") { }
///     .buttonStyle(GlassCTAStyle())
/// ```
struct GlassCTAStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        if #available(iOS 26, *) {
            configuration.label
                .font(.system(size: 16, weight: .bold))
                .tracking(0.4)
                .textCase(.uppercase)
                .foregroundStyle(Theme.Colors.textPrimary)
                .frame(maxWidth: .infinity, minHeight: 56)
                .glassEffect(.regular.tint(Theme.Colors.accent.opacity(0.15)).interactive(),
                             in: .rect(cornerRadius: Theme.Radius.md))
                .opacity(configuration.isPressed ? 0.85 : 1.0)
                .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
                .animation(Theme.Motion.snappy, value: configuration.isPressed)
        } else {
            configuration.label
                .font(.system(size: 16, weight: .bold))
                .tracking(0.4)
                .textCase(.uppercase)
                .foregroundStyle(Theme.Colors.background)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(Theme.Colors.accent)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
                .opacity(configuration.isPressed ? 0.78 : 1.0)
                .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
                .animation(Theme.Motion.snappy, value: configuration.isPressed)
        }
    }
}

// MARK: - Glass Effect Container Wrapper

/// Wraps content in a `GlassEffectContainer` on iOS 26+ for
/// coordinated morphing and blending between sibling glass views.
/// On earlier versions, just passes content through.
struct GlassContainer<Content: View>: View {
    var spacing: CGFloat
    @ViewBuilder var content: () -> Content

    init(spacing: CGFloat = 20, @ViewBuilder content: @escaping () -> Content) {
        self.spacing = spacing
        self.content = content
    }

    var body: some View {
        if #available(iOS 26, *) {
            GlassEffectContainer(spacing: spacing) {
                content()
            }
        } else {
            content()
        }
    }
}

// MARK: - View Extensions

extension View {

    /// Glass card (padded, full-width, rounded).
    func glassCard(cornerRadius: CGFloat = Theme.Radius.lg) -> some View {
        modifier(GlassCardModifier(cornerRadius: cornerRadius))
    }

    /// Glass surface (just the material, no layout).
    func glassSurface(cornerRadius: CGFloat = Theme.Radius.md) -> some View {
        modifier(GlassSurfaceModifier(cornerRadius: cornerRadius))
    }

    /// Glass popup / sheet background.
    func glassPopup() -> some View {
        modifier(GlassPopupModifier())
    }

    /// Glass treatment for tappable / interactive elements.
    func glassInteractive(cornerRadius: CGFloat = Theme.Radius.md) -> some View {
        modifier(GlassInteractiveModifier(cornerRadius: cornerRadius))
    }
}
