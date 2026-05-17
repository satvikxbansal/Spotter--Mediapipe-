import SwiftUI
import UIKit

struct V2MainShellView: View {
    @EnvironmentObject private var themeStore: ThemeStore
#if DEBUG
    @EnvironmentObject private var backendStatusStore: BackendStatusStore
    @EnvironmentObject private var designSystemV2Toggle: DesignSystemV2ToggleStore
#endif
    @Environment(\.appLevelPresenter) private var appLevelPresenter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var selectedTab: V2Tab
    @State private var isKeyboardVisible = false
    private let navStyleOverride: V2NavStyle?
#if DEBUG
    @State private var isShowingBackendStatusSheet = false
#endif

    init(initialSelectedTab: V2Tab = .dashboard, navStyleOverride: V2NavStyle? = nil) {
        _selectedTab = State(initialValue: initialSelectedTab)
        self.navStyleOverride = navStyleOverride
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                selectedContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(SpotterV2.Tokens.background)

#if DEBUG
                debugBackendStatusOverlay(topInset: proxy.safeAreaInsets.top)
#endif

                if !shouldHideNavigation {
                    V2LiquidGlassTabBar(
                        selectedTab: $selectedTab,
                        theme: themeStore.selectedTheme,
                        navStyleOverride: navStyleOverride
                    )
                    .padding(.bottom, proxy.safeAreaInsets.bottom + 10)
                    .transition(reduceMotion ? .identity : .move(edge: .bottom).combined(with: .opacity))
                    .zIndex(20)
                }
            }
            .animation(reduceMotion ? nil : SpotterV2.Motion.snappy, value: shouldHideNavigation)
        }
        .background(SpotterV2.Tokens.background)
        .preferredColorScheme(.dark)
        .accessibilityIdentifier("V2MainShellView")
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            isKeyboardVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            isKeyboardVisible = false
        }
#if DEBUG
        .sheet(isPresented: $isShowingBackendStatusSheet) {
            V2BackendStatusSheet(
                mode: backendStatusStore.activeBackendMode,
                desiredMode: backendStatusStore.desiredBackendMode,
                bootstrapState: backendStatusStore.firebaseBootstrapState,
                message: backendStatusStore.userFacingMessage,
                theme: themeStore.selectedTheme
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
#endif
    }

    private var shouldHideNavigation: Bool {
        isKeyboardVisible || appLevelPresenter.wrappedValue.isLiveWorkoutPresented
    }

    @ViewBuilder
    private var selectedContent: some View {
        switch selectedTab {
        case .dashboard:
            V2DashboardPlaceholder(theme: themeStore.selectedTheme)
        case .camera:
            V2CameraPlaceholder(theme: themeStore.selectedTheme)
        case .trophies:
            V2TrophiesPlaceholder(theme: themeStore.selectedTheme)
        case .profile:
#if DEBUG
            V2ProfilePlaceholder(
                theme: themeStore.selectedTheme,
                onReturnToV1: {
                    designSystemV2Toggle.setOverride(.forceOff)
                }
            )
#else
            V2ProfilePlaceholder(theme: themeStore.selectedTheme)
#endif
        }
    }

#if DEBUG
    @ViewBuilder
    private func debugBackendStatusOverlay(topInset: CGFloat) -> some View {
        if backendStatusStore.activeBackendMode != .local {
            VStack {
                HStack {
                    Spacer()
                    Button {
                        HapticsEngine.shared.buttonTap()
                        isShowingBackendStatusSheet = true
                    } label: {
                        V2BackendStatusChip(
                            mode: backendStatusStore.activeBackendMode,
                            theme: themeStore.selectedTheme
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens basic sync diagnostics for this debug build.")
                }
                Spacer()
            }
            .padding(.top, topInset + SpotterV2.Spacing.sm)
            .padding(.trailing, SpotterV2.Spacing.md)
            .zIndex(30)
        }
    }
#endif
}

struct V2DashboardPlaceholder: View {
    let theme: SpotterThemeOption

    var body: some View {
        V2TabPlaceholderView(
            theme: theme,
            tab: .dashboard,
            phaseText: "Coming in D4",
            title: "Dashboard",
            bodyText: "Quick Start, Daily Plan, weekly recap, real stats, and evidence-backed insights land here next."
        )
    }
}

struct V2CameraPlaceholder: View {
    let theme: SpotterThemeOption

    var body: some View {
        V2TabPlaceholderView(
            theme: theme,
            tab: .camera,
            phaseText: "Coming in D4",
            title: "Camera",
            bodyText: "Free Analysis keeps its current V1 flow until the D4 form-check surface replaces this stub."
        )
    }
}

struct V2TrophiesPlaceholder: View {
    let theme: SpotterThemeOption

    var body: some View {
        V2TabPlaceholderView(
            theme: theme,
            tab: .trophies,
            phaseText: "Coming in D6",
            title: "Trophies",
            bodyText: "Earned, in-progress, locked, and coming-soon trophy states are deferred to the D6 trophy pass."
        )
    }
}

struct V2ProfilePlaceholder: View {
    let theme: SpotterThemeOption
#if DEBUG
    var onReturnToV1: (() -> Void)?
#endif

    var body: some View {
#if DEBUG
        if let onReturnToV1 {
            V2TabPlaceholderView(
                theme: theme,
                tab: .profile,
                phaseText: "Coming in D6",
                title: "Profile",
                bodyText: "Themes, heatmap, history, export, delete-account, and sync diagnostics are styled in the D6 pass.",
                accessory: {
                    V2SecondaryButton(
                        title: "Return to V1",
                        systemImage: "arrow.uturn.backward",
                        theme: theme,
                        action: onReturnToV1
                    )
                    .accessibilityHint("Forces Design System V2 off in this debug build.")
                }
            )
        } else {
            placeholder
        }
#else
        placeholder
#endif
    }

    private var placeholder: some View {
        V2TabPlaceholderView(
            theme: theme,
            tab: .profile,
            phaseText: "Coming in D6",
            title: "Profile",
            bodyText: "Themes, heatmap, history, export, delete-account, and sync diagnostics are styled in the D6 pass."
        )
    }
}

private struct V2TabPlaceholderView<Accessory: View>: View {
    let theme: SpotterThemeOption
    let tab: V2Tab
    let phaseText: String
    let title: String
    let bodyText: String
    let accessory: Accessory

    init(
        theme: SpotterThemeOption,
        tab: V2Tab,
        phaseText: String,
        title: String,
        bodyText: String,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.theme = theme
        self.tab = tab
        self.phaseText = phaseText
        self.title = title
        self.bodyText = bodyText
        self.accessory = accessory()
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: SpotterV2.Spacing.xl) {
                Spacer(minLength: SpotterV2.Spacing.xxxl)

                V2StatusPill(theme: theme, label: phaseText, pulsingDot: false)

                VStack(alignment: .leading, spacing: SpotterV2.Spacing.md) {
                    Image(systemName: tab.systemImage)
                        .font(.system(size: 34, weight: .black))
                        .foregroundStyle(SpotterV2.Tokens.primary(theme))
                        .frame(width: 68, height: 68)
                        .background(SpotterV2.Tokens.primary(theme).opacity(0.14))
                        .clipShape(RoundedRectangle(cornerRadius: SpotterV2.Radius.lg))
                        .overlay(
                            RoundedRectangle(cornerRadius: SpotterV2.Radius.lg)
                                .stroke(SpotterV2.Tokens.primary(theme).opacity(0.42), lineWidth: 1)
                        )

                    Text(title)
                        .font(SpotterV2Typography.display(size: 46))
                        .italic()
                        .textCase(.uppercase)
                        .foregroundStyle(SpotterV2.Tokens.foreground)
                        .lineLimit(2)
                        .minimumScaleFactor(0.56)

                    Text(bodyText)
                        .font(SpotterV2Typography.body(size: 16, weight: .semibold))
                        .foregroundStyle(SpotterV2.Tokens.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(title). \(phaseText). \(bodyText)")

                accessory

                Spacer(minLength: 132)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(SpotterV2.Spacing.xl)
        }
    }
}

private extension V2TabPlaceholderView where Accessory == EmptyView {
    init(
        theme: SpotterThemeOption,
        tab: V2Tab,
        phaseText: String,
        title: String,
        bodyText: String
    ) {
        self.init(
            theme: theme,
            tab: tab,
            phaseText: phaseText,
            title: title,
            bodyText: bodyText,
            accessory: { EmptyView() }
        )
    }
}

#if DEBUG
private struct V2BackendStatusSheet: View {
    let mode: BackendMode
    let desiredMode: BackendMode
    let bootstrapState: FirebaseBootstrapState
    let message: String?
    let theme: SpotterThemeOption

    var body: some View {
        VStack(alignment: .leading, spacing: SpotterV2.Spacing.lg) {
            V2SectionHeader(title: "Sync diagnostics", trailingTitle: "D6 deferred")

            V2Card(theme: theme, borderColor: SpotterV2.Tokens.primary(theme).opacity(0.55)) {
                VStack(alignment: .leading, spacing: SpotterV2.Spacing.sm) {
                    diagnosticsRow("Active", mode.displayName)
                    diagnosticsRow("Desired", desiredMode.displayName)
                    diagnosticsRow("Firebase", bootstrapState.displayName)
                    diagnosticsRow("Message", message ?? "No backend warning.")
                }
            }

            Text("The full V2 sync diagnostics screen is deferred to D6; this sheet keeps the DEBUG backend status reachable in the D2 shell.")
                .font(SpotterV2Typography.body(size: 13, weight: .semibold))
                .foregroundStyle(SpotterV2.Tokens.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(SpotterV2.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(SpotterV2.Tokens.background)
        .preferredColorScheme(.dark)
    }

    private func diagnosticsRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(SpotterV2Typography.caption())
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundStyle(SpotterV2.Tokens.primary(theme))
                .frame(width: 90, alignment: .leading)
            Text(value)
                .font(SpotterV2Typography.body(size: 14, weight: .semibold))
                .foregroundStyle(SpotterV2.Tokens.foreground)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}
#endif

private struct V2MainShellView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            ForEach(SpotterThemeOption.allCases) { theme in
                ForEach(V2Tab.allCases) { tab in
                    V2ShellPreviewHost(theme: theme, selectedTab: tab, reduceTransparency: false)
                        .previewDisplayName("\(theme.displayName) \(tab.title) Glass SE")
                        .previewDevice("iPhone SE (3rd generation)")
                    V2ShellPreviewHost(theme: theme, selectedTab: tab, reduceTransparency: true)
                        .previewDisplayName("\(theme.displayName) \(tab.title) Solid Pro Max")
                        .previewDevice("iPhone 17 Pro Max")
                }
            }
        }
    }
}

private struct V2ShellPreviewHost: View {
    let theme: SpotterThemeOption
    let selectedTab: V2Tab
    let reduceTransparency: Bool
    @State private var appPresentation = AppLevelPresentationState()

    var body: some View {
        V2MainShellView(
            initialSelectedTab: selectedTab,
            navStyleOverride: reduceTransparency ? .solid : .liquidGlass
        )
            .environmentObject(ThemeStore(defaultTheme: theme))
            .environmentObject(BackendStatusStore())
            .environmentObject(
                DesignSystemV2ToggleStore(
                    remoteFlagSnapshotProvider: { true },
                    userDefaults: UserDefaults(suiteName: "V2ShellPreview.DesignSystemV2.\(theme.rawValue).\(selectedTab.rawValue)") ?? .standard
                )
            )
            .environment(\.appLevelPresenter, $appPresentation)
    }
}
