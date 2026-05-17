import SwiftUI

nonisolated enum V2NavStyle: Equatable {
    case liquidGlass
    case solid

    static func resolved(reduceTransparency: Bool) -> V2NavStyle {
        reduceTransparency ? .solid : .liquidGlass
    }
}

nonisolated enum V2Tab: String, CaseIterable, Identifiable {
    case dashboard
    case camera
    case trophies
    case profile

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard:
            return "Dashboard"
        case .camera:
            return "Camera"
        case .trophies:
            return "Trophies"
        case .profile:
            return "Profile"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard:
            return "house.fill"
        case .camera:
            return "camera.fill"
        case .trophies:
            return "trophy.fill"
        case .profile:
            return "person.fill"
        }
    }
}

struct V2LiquidGlassTabBar: View {
    @Binding var selectedTab: V2Tab
    let theme: SpotterThemeOption
    var navStyleOverride: V2NavStyle?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var resolvedNavStyle: V2NavStyle {
        navStyleOverride ?? V2NavStyle.resolved(reduceTransparency: reduceTransparency)
    }

    var body: some View {
        GeometryReader { proxy in
            let barWidth = min(proxy.size.width * 0.92, 440)

            ZStack {
                if resolvedNavStyle == .liquidGlass {
                    navGlow(width: barWidth)
                        .ignoresSafeArea(edges: .bottom)
                }

                HStack(spacing: 0) {
                    ForEach(V2Tab.allCases) { tab in
                        V2LiquidGlassTabButton(
                            tab: tab,
                            theme: theme,
                            isSelected: selectedTab == tab,
                            reduceMotion: reduceMotion
                        ) {
                            HapticsEngine.shared.buttonTap()
                            withAnimation(reduceMotion ? nil : SpotterV2.Motion.snappy) {
                                selectedTab = tab
                            }
                        }
                    }
                }
                .padding(.horizontal, SpotterV2.Spacing.xs)
                .frame(width: barWidth, height: 92)
                .background {
                    navBackground(style: resolvedNavStyle)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .frame(height: 92)
    }

    private func navGlow(width: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 54)
            .fill(Color.black.opacity(0.42))
            .frame(width: width, height: 98)
            .blur(radius: 22)
            .offset(y: 18)
    }

    @ViewBuilder
    func navBackground(style: V2NavStyle) -> some View {
        switch style {
        case .liquidGlass:
            EmptyView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .glassSurface(cornerRadius: 46)
                .overlay(
                    RoundedRectangle(cornerRadius: 46)
                        .stroke(Color.white.opacity(0.20), lineWidth: 2)
                )
                .shadow(color: .black.opacity(0.8), radius: 25, y: 12)
        case .solid:
            RoundedRectangle(cornerRadius: 46)
                .fill(Color.black.opacity(0.85))
                .overlay(
                    RoundedRectangle(cornerRadius: 46)
                        .stroke(SpotterV2.Tokens.border, lineWidth: 2)
                )
        }
    }
}

private struct V2LiquidGlassTabButton: View {
    let tab: V2Tab
    let theme: SpotterThemeOption
    let isSelected: Bool
    let reduceMotion: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: tab.systemImage)
                .font(.system(size: 30, weight: .black))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isSelected ? SpotterV2.Tokens.primary(theme) : SpotterV2.Tokens.mutedForeground)
                .scaleEffect(isSelected ? 1.1 : 1)
                .frame(maxWidth: .infinity)
                .frame(height: 76)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 38)
                            .fill(Color.white.opacity(0.10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 38)
                                    .stroke(SpotterV2.Tokens.primary(theme).opacity(0.55), lineWidth: 1)
                            )
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: 38))
        }
        .buttonStyle(V2TabPressButtonStyle(reduceMotion: reduceMotion))
        .accessibilityLabel(tab.title)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }
}

private struct V2TabPressButtonStyle: ButtonStyle {
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.94 : 1)
            .animation(reduceMotion ? nil : SpotterV2.Motion.press, value: configuration.isPressed)
    }
}

private struct V2LiquidGlassTabBar_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            ForEach(SpotterThemeOption.allCases) { theme in
                ForEach(V2Tab.allCases) { tab in
                    V2TabBarPreviewHost(theme: theme, selectedTab: tab, reduceTransparency: false)
                        .previewDisplayName("\(theme.displayName) \(tab.title) Glass SE")
                        .previewDevice("iPhone SE (3rd generation)")
                    V2TabBarPreviewHost(theme: theme, selectedTab: tab, reduceTransparency: true)
                        .previewDisplayName("\(theme.displayName) \(tab.title) Solid Pro Max")
                        .previewDevice("iPhone 17 Pro Max")
                }
            }
        }
    }
}

private struct V2TabBarPreviewHost: View {
    let theme: SpotterThemeOption
    @State var selectedTab: V2Tab
    let reduceTransparency: Bool

    var body: some View {
        ZStack {
            SpotterV2.Tokens.background.ignoresSafeArea()
            VStack {
                Spacer()
                V2LiquidGlassTabBar(
                    selectedTab: $selectedTab,
                    theme: theme,
                    navStyleOverride: reduceTransparency ? .solid : .liquidGlass
                )
                    .padding(.bottom, 44)
            }
        }
        .preferredColorScheme(.dark)
    }
}
