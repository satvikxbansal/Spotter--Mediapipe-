import SwiftUI

struct V2WelcomeView: View {
    static let loginComingSoonTitle = "Sign in with Apple is coming soon"
    static let loginComingSoonMessage = "Spotter is local-first today. Apple sign-in and account recovery are deferred until the backend account flow is ready."

    let onStart: () -> Void

    @EnvironmentObject private var themeStore: ThemeStore
    @State private var isShowingLoginComingSoon = false

    var body: some View {
        GeometryReader { proxy in
            let isCompact = proxy.size.height < 820

            VStack(alignment: .leading, spacing: isCompact ? SpotterV2.Spacing.sm : SpotterV2.Spacing.md) {
                header(compact: isCompact)

                heroCard(
                    compact: isCompact,
                    height: heroHeight(for: proxy, compact: isCompact)
                )

                childCards(compact: isCompact)

                Spacer(minLength: isCompact ? SpotterV2.Spacing.xxs : SpotterV2.Spacing.sm)

                bottomActions(compact: isCompact)
            }
            .padding(.horizontal, isCompact ? SpotterV2.Spacing.lg : SpotterV2.Spacing.xl)
            .padding(.top, topPadding(for: proxy, compact: isCompact))
            .padding(.bottom, bottomPadding(for: proxy, compact: isCompact))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(SpotterV2.Tokens.background)
        }
        .alert(Self.loginComingSoonTitle, isPresented: $isShowingLoginComingSoon) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(Self.loginComingSoonMessage)
        }
        .accessibilityIdentifier("V2WelcomeView")
    }

    private func topPadding(for _: GeometryProxy, compact: Bool) -> CGFloat {
        compact ? SpotterV2.Spacing.xs : SpotterV2.Spacing.sm
    }

    private func bottomPadding(for _: GeometryProxy, compact: Bool) -> CGFloat {
        compact ? SpotterV2.Spacing.xs : SpotterV2.Spacing.sm
    }

    private func heroHeight(for proxy: GeometryProxy, compact: Bool) -> CGFloat {
        if compact {
            return min(126, max(110, proxy.size.height * 0.16))
        }
        return min(150, max(132, proxy.size.height * 0.16))
    }

    private func bottomActions(compact: Bool) -> some View {
        VStack(spacing: compact ? SpotterV2.Spacing.xs : SpotterV2.Spacing.sm) {
            V2CTAButton(
                title: "Get Started",
                systemImage: "arrow.right",
                theme: themeStore.selectedTheme,
                action: onStart
            )

            loginLink
        }
    }

    private func header(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? SpotterV2.Spacing.md : SpotterV2.Spacing.lg) {
            HStack(spacing: SpotterV2.Spacing.sm) {
                Image(systemName: "viewfinder")
                    .font(.system(size: compact ? 19 : 21, weight: .black))
                    .foregroundStyle(.black)
                    .frame(width: compact ? 38 : 42, height: compact ? 38 : 42)
                    .background(SpotterV2.Tokens.primary(themeStore.selectedTheme))
                    .clipShape(Circle())

                Text("Spotter AI")
                    .font(SpotterV2Typography.heading(size: compact ? 14 : 16, weight: .black))
                    .fontWidth(.compressed)
                    .tracking(compact ? 2.6 : 3.2)
                    .textCase(.uppercase)
                    .foregroundStyle(SpotterV2.Tokens.mutedForeground)
            }

            VStack(alignment: .leading, spacing: 0) {
                Text("Your")
                Text("AI Form")
                Text("Coach")
                    .foregroundStyle(SpotterV2.Tokens.primary(themeStore.selectedTheme))
            }
            .font(SpotterV2Typography.display(size: compact ? 52 : 60))
            .fontWidth(.compressed)
            .textCase(.uppercase)
            .foregroundStyle(SpotterV2.Tokens.foreground)
            .lineLimit(1)
            .minimumScaleFactor(0.56)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Your AI Form Coach")
        }
    }

    private func heroCard(compact: Bool, height: CGFloat) -> some View {
        V2Card(
            theme: themeStore.selectedTheme,
            radius: SpotterV2.Radius.xl,
            padding: compact ? SpotterV2.Spacing.sm : SpotterV2.Spacing.md,
            borderColor: SpotterV2.Tokens.primary(themeStore.selectedTheme),
            hardShadowColor: SpotterV2.Tokens.primary(themeStore.selectedTheme).opacity(0.18)
        ) {
            ZStack(alignment: .topLeading) {
                Image("SpotterWelcomeHero")
                    .resizable()
                    .scaledToFill()
                    .saturation(0)
                    .opacity(0.30)
                    .frame(maxWidth: .infinity)
                    .frame(height: height)
                    .clipped()
                    .overlay(
                        LinearGradient(
                            colors: [
                                SpotterV2.Tokens.background.opacity(0.90),
                                SpotterV2.Tokens.background.opacity(0.80),
                                SpotterV2.Tokens.background.opacity(0.12)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: SpotterV2.Radius.lg))

                VStack(alignment: .leading, spacing: compact ? SpotterV2.Spacing.xs : SpotterV2.Spacing.sm) {
                    HStack(alignment: .top) {
                        Image(systemName: "viewfinder")
                            .font(.system(size: compact ? 21 : 24, weight: .black))
                            .foregroundStyle(.black)
                            .frame(width: compact ? 46 : 52, height: compact ? 46 : 52)
                            .background(SpotterV2.Tokens.primary(themeStore.selectedTheme))
                            .clipShape(RoundedRectangle(cornerRadius: SpotterV2.Radius.md))
                            .overlay(
                                RoundedRectangle(cornerRadius: SpotterV2.Radius.md)
                                    .stroke(.black, lineWidth: SpotterV2.BorderWidth.standard)
                            )

                        Spacer()

                        V2StatusPill(theme: themeStore.selectedTheme, label: "Live Tracking", pulsingDot: true)
                    }

                    Spacer(minLength: 0)

                    VStack(alignment: .leading, spacing: SpotterV2.Spacing.xxs) {
                        Text("Elite Form & REP AI")
                            .font(SpotterV2Typography.heading(size: compact ? 18 : 21))
                            .fontWidth(.compressed)
                            .textCase(.uppercase)
                            .foregroundStyle(SpotterV2.Tokens.foreground)
                            .lineLimit(1)
                            .minimumScaleFactor(0.64)
                        Text("Real-time coaching for every set")
                            .font(SpotterV2Typography.caption())
                            .tracking(1.8)
                            .textCase(.uppercase)
                            .foregroundStyle(SpotterV2.Tokens.mutedForeground)
                            .lineLimit(2)
                    }
                }
                .padding(SpotterV2.Spacing.sm)
            }
            .frame(height: height)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Live Tracking. Elite Form and rep AI. Real-time coaching for every set.")
    }

    private func childCards(compact: Bool) -> some View {
        let cardHeight: CGFloat = compact ? 106 : 124
        let cardPadding: CGFloat = compact ? SpotterV2.Spacing.sm : SpotterV2.Spacing.md

        return LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: SpotterV2.Spacing.md),
                GridItem(.flexible(), spacing: SpotterV2.Spacing.md)
            ],
            spacing: SpotterV2.Spacing.md
        ) {
            V2Card(
                theme: themeStore.selectedTheme,
                radius: SpotterV2.Radius.xl,
                padding: cardPadding
            ) {
                VStack(alignment: .leading, spacing: compact ? SpotterV2.Spacing.sm : SpotterV2.Spacing.md) {
                    coachPreview(compact: compact)
                    Spacer(minLength: 0)
                    Text("Pick who gets\nto coach you")
                        .font(SpotterV2Typography.heading(size: compact ? 15 : 17))
                        .fontWidth(.compressed)
                        .textCase(.uppercase)
                        .foregroundStyle(SpotterV2.Tokens.foreground)
                        .lineLimit(3)
                        .minimumScaleFactor(0.62)
                }
                .frame(maxWidth: .infinity, minHeight: cardHeight, maxHeight: cardHeight, alignment: .leading)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Pick who gets to coach you")

            V2Card(
                theme: themeStore.selectedTheme,
                radius: SpotterV2.Radius.xl,
                padding: cardPadding
            ) {
                VStack(alignment: .leading, spacing: compact ? SpotterV2.Spacing.sm : SpotterV2.Spacing.md) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: compact ? 30 : 34, weight: .black))
                        .foregroundStyle(SpotterV2.Tokens.foreground)
                    Spacer(minLength: 0)
                    Text("100% Local\n& Secure")
                        .font(SpotterV2Typography.heading(size: compact ? 15 : 17))
                        .fontWidth(.compressed)
                        .textCase(.uppercase)
                        .foregroundStyle(SpotterV2.Tokens.foreground)
                        .lineLimit(3)
                        .minimumScaleFactor(0.62)
                }
                .frame(maxWidth: .infinity, minHeight: cardHeight, maxHeight: cardHeight, alignment: .leading)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("100 percent local and secure")
        }
    }

    private func coachPreview(compact: Bool) -> some View {
        let size: CGFloat = compact ? 38 : 44

        return HStack(spacing: compact ? -11 : -12) {
            coachAvatar(assetName: "CoachBennet", ringColor: SpotterV2.Tokens.primary(themeStore.selectedTheme), size: size)
            coachAvatar(assetName: "CoachFletcher", ringColor: SpotterV2.Tokens.chart1, size: size)
            Image(systemName: "plus")
                .font(.system(size: compact ? 17 : 19, weight: .black))
                .foregroundStyle(SpotterV2.Tokens.foreground)
                .frame(width: size, height: size)
                .background(SpotterV2.Tokens.secondary)
                .clipShape(Circle())
                .overlay(Circle().stroke(SpotterV2.Tokens.card, lineWidth: 2))
        }
    }

    private func coachAvatar(assetName: String, ringColor: Color, size: CGFloat) -> some View {
        Image(assetName)
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay(Circle().stroke(SpotterV2.Tokens.card, lineWidth: 2))
            .overlay(Circle().stroke(ringColor, lineWidth: 3).padding(-4))
    }

    private var loginLink: some View {
        Button {
            isShowingLoginComingSoon = true
        } label: {
            HStack(spacing: 4) {
                Text("Already have an account?")
                    .foregroundStyle(SpotterV2.Tokens.mutedForeground)
                Text("Log in")
                    .fontWeight(.black)
                    .foregroundStyle(SpotterV2.Tokens.foreground)
                    .underline()
            }
            .font(SpotterV2Typography.body(size: 15, weight: .semibold))
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Already have an account? Log in")
        .accessibilityHint(Self.loginComingSoonTitle)
    }
}

#if DEBUG
private struct V2WelcomeView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            ForEach(SpotterThemeOption.allCases) { theme in
                V2D3PreviewEnvironment(theme: theme) {
                    V2WelcomeView(onStart: {})
                }
                .previewDisplayName("\(theme.displayName) Welcome SE")
                .previewDevice("iPhone SE (3rd generation)")

                V2D3PreviewEnvironment(theme: theme) {
                    V2WelcomeView(onStart: {})
                }
                .previewDisplayName("\(theme.displayName) Welcome Pro Max")
                .previewDevice("iPhone 17 Pro Max")
            }
        }
    }
}
#endif
