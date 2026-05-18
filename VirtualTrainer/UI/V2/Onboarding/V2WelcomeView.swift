import SwiftUI

struct V2WelcomeView: View {
    static let loginComingSoonTitle = "Sign in with Apple is coming soon"
    static let loginComingSoonMessage = "Spotter is local-first today. Apple sign-in and account recovery are deferred until the backend account flow is ready."

    let onStart: () -> Void

    @EnvironmentObject private var themeStore: ThemeStore
    @State private var isShowingLoginComingSoon = false

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: SpotterV2.Spacing.xl) {
                        header
                            .padding(.top, max(proxy.safeAreaInsets.top + SpotterV2.Spacing.lg, SpotterV2.Spacing.xxxl))

                        VStack(spacing: SpotterV2.Spacing.md) {
                            heroCard
                            childCards
                        }
                    }
                    .padding(.horizontal, SpotterV2.Spacing.xl)
                    .padding(.bottom, bottomActionHeight(proxy))
                }

                bottomActions
                    .padding(.horizontal, SpotterV2.Spacing.xl)
                    .padding(.top, SpotterV2.Spacing.md)
                    .padding(.bottom, max(proxy.safeAreaInsets.bottom + SpotterV2.Spacing.sm, SpotterV2.Spacing.xl))
                    .background(bottomActionScrim)
            }
            .background(SpotterV2.Tokens.background)
        }
        .alert(Self.loginComingSoonTitle, isPresented: $isShowingLoginComingSoon) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(Self.loginComingSoonMessage)
        }
        .accessibilityIdentifier("V2WelcomeView")
    }

    private func bottomActionHeight(_ proxy: GeometryProxy) -> CGFloat {
        max(proxy.safeAreaInsets.bottom, SpotterV2.Spacing.xl) + 150
    }

    private var bottomActions: some View {
        VStack(spacing: SpotterV2.Spacing.lg) {
            V2CTAButton(
                title: "Get Started",
                systemImage: "arrow.right",
                theme: themeStore.selectedTheme,
                action: onStart
            )

            loginLink
        }
    }

    private var bottomActionScrim: some View {
        LinearGradient(
            colors: [
                SpotterV2.Tokens.background.opacity(0),
                SpotterV2.Tokens.background.opacity(0.94),
                SpotterV2.Tokens.background
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea(edges: .bottom)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: SpotterV2.Spacing.xl) {
            HStack(spacing: SpotterV2.Spacing.sm) {
                Image(systemName: "viewfinder")
                    .font(.system(size: 22, weight: .black))
                    .foregroundStyle(.black)
                    .frame(width: 42, height: 42)
                    .background(SpotterV2.Tokens.primary(themeStore.selectedTheme))
                    .clipShape(Circle())

                Text("Spotter AI")
                    .font(SpotterV2Typography.heading(size: 16, weight: .black))
                    .tracking(3.2)
                    .textCase(.uppercase)
                    .foregroundStyle(SpotterV2.Tokens.mutedForeground)
            }

            VStack(alignment: .leading, spacing: 0) {
                Text("Your")
                Text("AI Form")
                Text("Coach")
                    .foregroundStyle(SpotterV2.Tokens.primary(themeStore.selectedTheme))
            }
            .font(SpotterV2Typography.display(size: 62))
            .textCase(.uppercase)
            .foregroundStyle(SpotterV2.Tokens.foreground)
            .lineLimit(1)
            .minimumScaleFactor(0.56)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Your AI Form Coach")

            Text("Never train alone again.")
                .font(SpotterV2Typography.body(size: 20, weight: .semibold))
                .foregroundStyle(SpotterV2.Tokens.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var heroCard: some View {
        V2Card(
            theme: themeStore.selectedTheme,
            radius: SpotterV2.Radius.xl,
            padding: SpotterV2.Spacing.lg,
            borderColor: SpotterV2.Tokens.primary(themeStore.selectedTheme),
            hardShadowColor: SpotterV2.Tokens.primary(themeStore.selectedTheme).opacity(0.18)
        ) {
            ZStack(alignment: .topLeading) {
                Image("CoachBennet")
                    .resizable()
                    .scaledToFill()
                    .saturation(0)
                    .opacity(0.20)
                    .frame(maxWidth: .infinity, minHeight: 172)
                    .clipped()
                    .overlay(
                        LinearGradient(
                            colors: [
                                SpotterV2.Tokens.background,
                                SpotterV2.Tokens.background.opacity(0.84),
                                SpotterV2.Tokens.background.opacity(0.18)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: SpotterV2.Radius.lg))

                VStack(alignment: .leading, spacing: SpotterV2.Spacing.xl) {
                    HStack(alignment: .top) {
                        Image(systemName: "viewfinder")
                            .font(.system(size: 28, weight: .black))
                            .foregroundStyle(.black)
                            .frame(width: 58, height: 58)
                            .background(SpotterV2.Tokens.primary(themeStore.selectedTheme))
                            .clipShape(RoundedRectangle(cornerRadius: SpotterV2.Radius.md))
                            .overlay(
                                RoundedRectangle(cornerRadius: SpotterV2.Radius.md)
                                    .stroke(.black, lineWidth: SpotterV2.BorderWidth.standard)
                            )

                        Spacer()

                        V2StatusPill(theme: themeStore.selectedTheme, label: "Live Tracking", pulsingDot: true)
                    }

                    Spacer(minLength: SpotterV2.Spacing.lg)

                    VStack(alignment: .leading, spacing: SpotterV2.Spacing.xxs) {
                        Text("Elite Form & REP AI")
                            .font(SpotterV2Typography.heading(size: 24))
                            .textCase(.uppercase)
                            .foregroundStyle(SpotterV2.Tokens.foreground)
                            .lineLimit(2)
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
            .frame(minHeight: 172)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Live Tracking. Elite Form and rep AI. Real-time coaching for every set.")
    }

    private var childCards: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: SpotterV2.Spacing.md),
                GridItem(.flexible(), spacing: SpotterV2.Spacing.md)
            ],
            spacing: SpotterV2.Spacing.md
        ) {
            V2Card(
                theme: themeStore.selectedTheme,
                radius: SpotterV2.Radius.xl,
                padding: SpotterV2.Spacing.md
            ) {
                VStack(alignment: .leading) {
                    coachPreview
                    Spacer(minLength: SpotterV2.Spacing.xl)
                    Text("Pick who gets\nto coach you")
                        .font(SpotterV2Typography.heading(size: 19))
                        .textCase(.uppercase)
                        .foregroundStyle(SpotterV2.Tokens.foreground)
                        .lineLimit(3)
                        .minimumScaleFactor(0.62)
                }
                .aspectRatio(1, contentMode: .fit)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Pick who gets to coach you")

            V2Card(
                theme: themeStore.selectedTheme,
                radius: SpotterV2.Radius.xl,
                padding: SpotterV2.Spacing.md
            ) {
                VStack(alignment: .leading) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 31, weight: .black))
                        .foregroundStyle(SpotterV2.Tokens.foreground)
                    Spacer(minLength: SpotterV2.Spacing.xl)
                    Text("100% Local\n& Secure")
                        .font(SpotterV2Typography.heading(size: 19))
                        .textCase(.uppercase)
                        .foregroundStyle(SpotterV2.Tokens.foreground)
                        .lineLimit(3)
                        .minimumScaleFactor(0.62)
                }
                .aspectRatio(1, contentMode: .fit)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("100 percent local and secure")
        }
    }

    private var coachPreview: some View {
        HStack(spacing: -12) {
            coachAvatar(assetName: "CoachBennet", ringColor: SpotterV2.Tokens.primary(themeStore.selectedTheme))
            coachAvatar(assetName: "CoachFletcher", ringColor: SpotterV2.Tokens.chart1)
            Image(systemName: "plus")
                .font(.system(size: 20, weight: .black))
                .foregroundStyle(SpotterV2.Tokens.foreground)
                .frame(width: 46, height: 46)
                .background(SpotterV2.Tokens.secondary)
                .clipShape(Circle())
                .overlay(Circle().stroke(SpotterV2.Tokens.card, lineWidth: 2))
        }
    }

    private func coachAvatar(assetName: String, ringColor: Color) -> some View {
        Image(assetName)
            .resizable()
            .scaledToFill()
            .frame(width: 46, height: 46)
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
