import SwiftUI

// ────────────────────────────────────────────────────────────────────
// MARK: - DesignGalleryView
// ────────────────────────────────────────────────────────────────────

/// Mood board: every color, typeface, and haptic in one scrollable view.
/// Use this to validate the visual language before building features.
struct DesignGalleryView: View {

    @State private var repCount: Int = 0

    @State private var repFlash     = false
    @State private var warningFlash = false
    @State private var successFlash = false

    private let haptics = HapticsEngine.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxl) {

                masthead
                typographySection
                colorSection
                hapticSection

                Spacer(minLength: Theme.Spacing.xxxl)
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.top, Theme.Spacing.xl)
        }
        .scrollIndicators(.hidden)
        .background(Theme.Colors.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    // ────────────────────────────────────────────────────────────────
    // MARK: - Masthead
    // ────────────────────────────────────────────────────────────────

    private var masthead: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("Design System")
                .header(size: 36)

            Text("No-Fluff Noir  ·  Virtual Trainer")
                .subheader()
        }
        .padding(.bottom, Theme.Spacing.sm)
    }

    // ────────────────────────────────────────────────────────────────
    // MARK: - Typography
    // ────────────────────────────────────────────────────────────────

    private var typographySection: some View {
        card(label: "TYPOGRAPHY") {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {

                specimen(
                    meta: "Rep Counter  ·  .black  ·  80pt  ·  Rounded  ·  Tabular"
                ) {
                    Text("\(repCount)")
                        .repCounter()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .onTapGesture {
                            withAnimation(Theme.Motion.snappy) { repCount += 1 }
                            haptics.repTick()
                        }
                }

                specimen(meta: "Header  ·  .heavy  ·  uppercase  ·  tight tracking") {
                    Text("Goblet Squat")
                        .header()
                }

                specimen(meta: "Subheader  ·  .bold  ·  muted") {
                    Text("4 sets  ·  10 reps  ·  30s rest")
                        .subheader()
                }

                specimen(meta: "Body  ·  .medium  ·  16pt") {
                    Text("Hold the weight close to your chest. Push your hips back and lower until your thighs are parallel, then drive through your heels.")
                        .bodyText()
                        .lineSpacing(4)
                }

                specimen(meta: "Caption  ·  .semibold  ·  12pt") {
                    Text("Last performed 2 days ago")
                        .caption()
                }
            }
        }
    }

    // ────────────────────────────────────────────────────────────────
    // MARK: - Colors
    // ────────────────────────────────────────────────────────────────

    private var colorSection: some View {
        card(label: "PALETTE") {
            VStack(spacing: Theme.Spacing.sm) {

                // Surfaces
                swatchRow([
                    ("Background",  Theme.Colors.background, true),
                    ("Surface",     Theme.Colors.surface,    false),
                    ("Raised",      Theme.Colors.surfaceRaised, false)
                ])

                // Accent + semantic
                swatchRow([
                    ("Amber",       Theme.Colors.accent,     false),
                    ("Amber Muted", Color(red: 1.0, green: 0.69, blue: 0.0).opacity(0.20), false),
                    ("Danger",      Theme.Colors.danger,     false)
                ])

                // Text hierarchy
                swatchRow([
                    ("Primary",   Theme.Colors.textPrimary,   false),
                    ("Secondary", Theme.Colors.textSecondary,  false),
                    ("Tertiary",  Theme.Colors.textTertiary,   false)
                ])
            }
        }
    }

    // ────────────────────────────────────────────────────────────────
    // MARK: - Haptics & Components
    // ────────────────────────────────────────────────────────────────

    private var hapticSection: some View {
        card(label: "COMPONENTS & HAPTICS") {
            VStack(spacing: Theme.Spacing.md) {

                hapticButton(
                    icon: "bolt.fill",
                    title: "Rep Tick",
                    subtitle: "Sharp transient · max intensity",
                    flash: $repFlash,
                    flashColor: Theme.Colors.accent
                ) {
                    haptics.repTick()
                }

                hapticButton(
                    icon: "exclamationmark.triangle.fill",
                    title: "Warning Pulse",
                    subtitle: "Double knock · form correction",
                    flash: $warningFlash,
                    flashColor: Theme.Colors.danger
                ) {
                    haptics.warningPulse()
                }

                hapticButton(
                    icon: "trophy.fill",
                    title: "Success Ripple",
                    subtitle: "Ascending 3-beat crescendo",
                    flash: $successFlash,
                    flashColor: Theme.Colors.positive
                ) {
                    haptics.successRipple()
                }

                // Secondary / ghost button demo
                Button {
                    haptics.buttonTap()
                } label: {
                    Text("Ghost Button Demo")
                }
                .buttonStyle(SecondaryCTAStyle())
                .padding(.top, Theme.Spacing.xs)
            }
        }
    }

    // ────────────────────────────────────────────────────────────────
    // MARK: - Reusable Components
    // ────────────────────────────────────────────────────────────────

    /// Section card with a tinted section label.
    private func card<Content: View>(
        label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            Text(label)
                .font(.system(size: 11, weight: .heavy))
                .tracking(1.8)
                .textCase(.uppercase)
                .foregroundStyle(Theme.Colors.accent)

            content()
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg))
    }

    /// Metadata label + content pair for typography specimens.
    private func specimen<Content: View>(
        meta: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(meta)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.Colors.textTertiary)

            content()
        }
    }

    /// Haptic test button with icon, title, subtitle, and edge flash.
    private func hapticButton(
        icon: String,
        title: String,
        subtitle: String,
        flash: Binding<Bool>,
        flashColor: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            action()
            flash.wrappedValue = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                flash.wrappedValue = false
            }
        } label: {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(flashColor)
                    .frame(width: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Theme.Colors.textPrimary)

                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.Colors.textTertiary)
                }

                Spacer()

                Image(systemName: "hand.tap.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .frame(maxWidth: .infinity, minHeight: 60)
            .background(Theme.Colors.surfaceRaised)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.md)
                    .stroke(flashColor, lineWidth: flash.wrappedValue ? 1.5 : 0)
                    .opacity(flash.wrappedValue ? 1 : 0)
            )
            .scaleEffect(flash.wrappedValue ? 1.02 : 1.0)
            .animation(Theme.Motion.snappy, value: flash.wrappedValue)
        }
        .buttonStyle(.plain)
    }

    /// Row of equally-sized color swatches.
    private func swatchRow(_ items: [(String, Color, Bool)]) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            ForEach(items, id: \.0) { name, color, bordered in
                VStack(spacing: Theme.Spacing.xxs) {
                    RoundedRectangle(cornerRadius: Theme.Radius.sm)
                        .fill(color)
                        .frame(height: 52)
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.Radius.sm)
                                .stroke(
                                    bordered ? Theme.Colors.divider : .clear,
                                    lineWidth: 1
                                )
                        )

                    Text(name)
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
        }
    }
}

// ────────────────────────────────────────────────────────────────────
// MARK: - Preview
// ────────────────────────────────────────────────────────────────────

#Preview {
    DesignGalleryView()
}
