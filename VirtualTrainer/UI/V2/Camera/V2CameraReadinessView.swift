import SwiftUI
import UIKit

nonisolated struct V2CameraReadinessUIState: Equatable {
    enum Kind: Equatable {
        case ready
        case permissionDenied
        case visibilityIssue
        case countdown
        case waiting
    }

    let kind: Kind
    let title: String
    let message: String
    let phaseIndex: Int
    let systemImage: String
    let primaryActionTitle: String?
    let secondaryActionTitle: String?
    let shouldPulse: Bool

    static let ready = V2CameraReadinessUIState(
        kind: .ready,
        title: "Ready",
        message: "Full body is visible. Start when you're set.",
        phaseIndex: 3,
        systemImage: "person.crop.square",
        primaryActionTitle: "Start Tracking",
        secondaryActionTitle: nil,
        shouldPulse: false
    )

    static let permissionDenied = V2CameraReadinessUIState(
        kind: .permissionDenied,
        title: "Camera access is off",
        message: "Open Settings and allow camera access. Spotter does not store or upload camera frames.",
        phaseIndex: 1,
        systemImage: "camera.fill",
        primaryActionTitle: nil,
        secondaryActionTitle: "Open Settings",
        shouldPulse: false
    )

    static func visibilityIssue(title: String, message: String) -> V2CameraReadinessUIState {
        V2CameraReadinessUIState(
            kind: .visibilityIssue,
            title: title,
            message: message,
            phaseIndex: 1,
            systemImage: "person.crop.square",
            primaryActionTitle: nil,
            secondaryActionTitle: nil,
            shouldPulse: true
        )
    }

    static func countdown(seconds: Int) -> V2CameraReadinessUIState {
        V2CameraReadinessUIState(
            kind: .countdown,
            title: "\(seconds)",
            message: "Get set.",
            phaseIndex: 2,
            systemImage: "timer",
            primaryActionTitle: nil,
            secondaryActionTitle: nil,
            shouldPulse: true
        )
    }

    static func waiting(seconds: Int) -> V2CameraReadinessUIState {
        V2CameraReadinessUIState(
            kind: .waiting,
            title: "Take your time",
            message: "Spotter will ask again in \(seconds).",
            phaseIndex: 1,
            systemImage: "hand.raised.fill",
            primaryActionTitle: nil,
            secondaryActionTitle: nil,
            shouldPulse: false
        )
    }
}

nonisolated enum V2CameraReadinessAdapter {
    static func makeState(
        permissionStatus: CameraPermissionStatus,
        visibilityResult: BodyVisibilityChecker.Result,
        coordinatorState: WorkoutReadyState,
        setupInstruction: String
    ) -> V2CameraReadinessUIState {
        if permissionStatus == .denied {
            return .permissionDenied
        }

        switch coordinatorState {
        case .countdown(let secondsLeft):
            return .countdown(seconds: secondsLeft)
        case .waitingToRetry(let secondsLeft):
            return .waiting(seconds: secondsLeft)
        case .askingReady where visibilityResult.isReady,
             .exerciseActive where visibilityResult.isReady:
            return .ready
        default:
            return .visibilityIssue(
                title: visibilityIssueTitle(for: visibilityResult.message),
                message: visibilityResult.message ?? setupInstruction
            )
        }
    }

    private static func visibilityIssueTitle(for message: String?) -> String {
        guard let message else { return "Step into frame" }
        let lowercased = message.lowercased()
        if lowercased.contains("move back") || lowercased.contains("too close") {
            return "Move back"
        }
        if lowercased.contains("step into") {
            return "Step into frame"
        }
        return "Adjust position"
    }
}

struct V2CameraReadinessView: View {
    let theme: SpotterThemeOption
    let state: V2CameraReadinessUIState
    let orientationInstruction: String
    let visibilityPercent: Int
    let onStartTracking: () -> Void
    let onOpenSettings: () -> Void
    let onClose: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPulsing = false

    var body: some View {
        ZStack {
            Image("SpotterCameraReadinessBackplate")
                .resizable()
                .scaledToFill()
                .saturation(0)
                .brightness(-0.28)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()
                .accessibilityHidden(true)

            SpotterV2.Tokens.background.opacity(0.42)
                .ignoresSafeArea()

            VStack {
                Spacer()
                readinessContent
                Spacer()
                orientationCard
                    .padding(.bottom, SpotterV2.Spacing.xl)
            }
            .padding(.horizontal, SpotterV2.Spacing.xl)

            closeButton
        }
        .onAppear {
            guard state.shouldPulse, !reduceMotion else { return }
            isPulsing = true
        }
        .onChange(of: state.shouldPulse) { _, shouldPulse in
            guard shouldPulse, !reduceMotion else {
                isPulsing = false
                return
            }
            isPulsing = true
        }
        .accessibilityIdentifier("V2CameraReadinessView")
    }

    static func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private var readinessContent: some View {
        VStack(spacing: SpotterV2.Spacing.xl) {
            ZStack {
                Image(systemName: state.systemImage)
                    .font(.system(size: 126, weight: .black))
                    .foregroundStyle(SpotterV2.Tokens.primary(theme).opacity(state.kind == .permissionDenied ? 0.34 : 0.22))
                    .accessibilityHidden(true)

                if state.shouldPulse {
                    Circle()
                        .fill(SpotterV2.Tokens.primary(theme))
                        .frame(width: 18, height: 18)
                        .scaleEffect(isPulsing && !reduceMotion ? 2.2 : 1)
                        .opacity(isPulsing && !reduceMotion ? 0.12 : 1)
                        .animation(reduceMotion ? nil : SpotterV2.Motion.pulse, value: isPulsing)
                        .accessibilityHidden(true)
                }
            }
            .frame(height: 176)

            VStack(spacing: SpotterV2.Spacing.md) {
                Text(state.title)
                    .font(SpotterV2Typography.display(size: state.kind == .countdown ? 82 : 42))
                    .fontWidth(.compressed)
                    .textCase(.uppercase)
                    .foregroundStyle(SpotterV2.Tokens.foreground)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.55)
                    .monospacedDigit()

                Text(state.message)
                    .font(SpotterV2Typography.body(size: 18, weight: .semibold))
                    .foregroundStyle(SpotterV2.Tokens.mutedForeground)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .frame(maxWidth: 320)
                    .fixedSize(horizontal: false, vertical: true)
            }

            phaseDots

            if state.kind == .visibilityIssue {
                visibilityIssueCard
            }

            VStack(spacing: SpotterV2.Spacing.md) {
                if let primaryActionTitle = state.primaryActionTitle {
                    V2CTAButton(
                        title: primaryActionTitle,
                        systemImage: "play.fill",
                        theme: theme,
                        action: onStartTracking
                    )
                }

                if let secondaryActionTitle = state.secondaryActionTitle {
                    V2SecondaryButton(
                        title: secondaryActionTitle,
                        systemImage: "gearshape.fill",
                        theme: theme,
                        action: onOpenSettings
                    )
                }
            }
            .frame(maxWidth: 360)
        }
        .accessibilityElement(children: .contain)
    }

    private var phaseDots: some View {
        HStack(spacing: SpotterV2.Spacing.xs) {
            ForEach(1...3, id: \.self) { index in
                Circle()
                    .fill(index == state.phaseIndex ? SpotterV2.Tokens.primary(theme) : SpotterV2.Tokens.primary(theme).opacity(0.20))
                    .frame(width: 9, height: 9)
            }
        }
        .accessibilityLabel("Readiness phase \(state.phaseIndex) of 3")
    }

    private var visibilityIssueCard: some View {
        HStack(spacing: SpotterV2.Spacing.sm) {
            Image(systemName: "figure.walk.motion")
                .font(.system(size: 21, weight: .black))
                .foregroundStyle(SpotterV2.Tokens.primary(theme))

            VStack(alignment: .leading, spacing: SpotterV2.Spacing.xxxs) {
                Text("Adjust position")
                    .font(SpotterV2Typography.caption())
                    .tracking(1.2)
                    .textCase(.uppercase)
                    .foregroundStyle(SpotterV2.Tokens.primary(theme))
                Text(state.message)
                    .font(SpotterV2Typography.body(size: 13, weight: .semibold))
                    .foregroundStyle(SpotterV2.Tokens.foreground)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            ZStack {
                Circle()
                    .stroke(SpotterV2.Tokens.secondary, lineWidth: 4)
                Circle()
                    .trim(from: 0, to: min(max(Double(visibilityPercent) / 100, 0), 1))
                    .stroke(
                        SpotterV2.Tokens.primary(theme),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                Text("\(visibilityPercent)")
                    .font(SpotterV2Typography.caption(weight: .bold))
                    .foregroundStyle(SpotterV2.Tokens.mutedForeground)
            }
            .frame(width: 38, height: 38)
        }
        .padding(SpotterV2.Spacing.md)
        .frame(maxWidth: 360)
        .background(SpotterV2.Tokens.secondary.opacity(0.82))
        .clipShape(RoundedRectangle(cornerRadius: SpotterV2.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: SpotterV2.Radius.lg)
                .stroke(SpotterV2.Tokens.primary(theme).opacity(0.24), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Adjust position. \(state.message). Visibility \(visibilityPercent) percent.")
    }

    private var orientationCard: some View {
        HStack(spacing: SpotterV2.Spacing.md) {
            Image(systemName: "iphone")
                .font(.system(size: 24, weight: .black))
                .rotationEffect(.degrees(12))
                .foregroundStyle(SpotterV2.Tokens.foreground)
                .frame(width: 44, height: 44)
                .background(SpotterV2.Tokens.foreground.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: SpotterV2.Radius.md))

            VStack(alignment: .leading, spacing: SpotterV2.Spacing.xxxs) {
                Text(orientationInstruction)
                    .font(SpotterV2Typography.caption())
                    .tracking(0.7)
                    .textCase(.uppercase)
                    .foregroundStyle(SpotterV2.Tokens.foreground.opacity(0.82))
                    .lineLimit(2)
                    .minimumScaleFactor(0.70)
                Text("Visibility \(visibilityPercent)%")
                    .font(SpotterV2Typography.caption(weight: .bold))
                    .tracking(0.7)
                    .textCase(.uppercase)
                    .foregroundStyle(SpotterV2.Tokens.mutedForeground)
            }

            Spacer(minLength: 0)
        }
        .padding(SpotterV2.Spacing.md)
        .background(SpotterV2.Tokens.secondary.opacity(0.82))
        .clipShape(RoundedRectangle(cornerRadius: SpotterV2.Radius.xl))
        .overlay(
            RoundedRectangle(cornerRadius: SpotterV2.Radius.xl)
                .stroke(SpotterV2.Tokens.border.opacity(0.22), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(orientationInstruction). Visibility \(visibilityPercent) percent.")
    }

    private var closeButton: some View {
        VStack {
            HStack {
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 22, weight: .black))
                        .foregroundStyle(SpotterV2.Tokens.foreground)
                        .frame(width: 56, height: 56)
                        .background(SpotterV2.Tokens.secondary.opacity(0.84))
                        .clipShape(RoundedRectangle(cornerRadius: SpotterV2.Radius.lg))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close readiness")
            }
            .padding(.top, 54)
            .padding(.trailing, SpotterV2.Spacing.xl)

            Spacer()
        }
    }
}

#if DEBUG
private struct V2CameraReadinessView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            ForEach(SpotterThemeOption.allCases) { theme in
                V2CameraReadinessPreviewHost(theme: theme, state: .ready)
                    .previewDisplayName("\(theme.displayName) Camera Ready SE")
                    .previewDevice("iPhone SE (3rd generation)")

                V2CameraReadinessPreviewHost(theme: theme, state: .ready)
                    .previewDisplayName("\(theme.displayName) Camera Ready Pro Max")
                    .previewDevice("iPhone 17 Pro Max")
            }

            V2CameraReadinessPreviewHost(theme: .hyper, state: .permissionDenied)
                .previewDisplayName("Permission Denied")
                .previewDevice("iPhone 17 Pro Max")
        }
    }
}

private struct V2CameraReadinessPreviewHost: View {
    let theme: SpotterThemeOption
    let state: V2CameraReadinessUIState

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [SpotterV2.Tokens.secondary, SpotterV2.Tokens.background],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            V2CameraReadinessView(
                theme: theme,
                state: state,
                orientationInstruction: "Turn phone sideways for squats",
                visibilityPercent: state.kind == .ready ? 100 : 42,
                onStartTracking: {},
                onOpenSettings: {},
                onClose: {}
            )
        }
        .preferredColorScheme(.dark)
    }
}
#endif
