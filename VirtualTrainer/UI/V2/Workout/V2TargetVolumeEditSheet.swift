import SwiftUI

struct V2TargetVolumeEditSheet: View {
    let theme: SpotterThemeOption
    let initialDraft: TargetVolumeDraft
    let onSave: (TargetVolumeDraft) -> TargetVolumeValidation
    let onReset: (PlanExerciseIdentifier) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: TargetVolumeDraft
    @State private var validationMessage: String?

    init(
        theme: SpotterThemeOption,
        draft: TargetVolumeDraft,
        onSave: @escaping (TargetVolumeDraft) -> TargetVolumeValidation,
        onReset: @escaping (PlanExerciseIdentifier) -> Void
    ) {
        self.theme = theme
        self.initialDraft = draft
        self.onSave = onSave
        self.onReset = onReset
        _draft = State(initialValue: draft)
        _validationMessage = State(initialValue: draft.validationMessage)
    }

    var body: some View {
        V2BottomSheetShell(
            theme: theme,
            title: "Adjust Movement",
            onClose: { dismiss() }
        ) {
            VStack(alignment: .leading, spacing: SpotterV2.Spacing.lg) {
                exerciseHeader
                heroTarget
                stepperStack
                messageView
                actionButtons
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
        .preferredColorScheme(.dark)
    }

    private var exerciseHeader: some View {
        VStack(alignment: .leading, spacing: SpotterV2.Spacing.xxs) {
            Text(draft.originalExerciseType.displayName)
                .font(SpotterV2Typography.display(size: 34))
                .fontWidth(.compressed)
                .italic()
                .textCase(.uppercase)
                .foregroundStyle(SpotterV2.Tokens.foreground)
                .lineLimit(2)
                .minimumScaleFactor(0.58)
        }
    }

    private var heroTarget: some View {
        V2Card(
            theme: theme,
            radius: SpotterV2.Radius.lg,
            borderColor: SpotterV2.Tokens.primary(theme).opacity(0.72),
            hardShadowColor: SpotterV2.Tokens.primary(theme).opacity(0.22)
        ) {
            VStack(alignment: .leading, spacing: SpotterV2.Spacing.xs) {
                Text("Target Volume")
                    .font(SpotterV2Typography.caption())
                    .tracking(1.4)
                    .textCase(.uppercase)
                    .foregroundStyle(SpotterV2.Tokens.mutedForeground)

                Text(targetSummary)
                    .font(SpotterV2Typography.mono(size: 44))
                    .monospacedDigit()
                    .foregroundStyle(SpotterV2.Tokens.primary(theme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.45)
                    .accessibilityLabel("Target \(targetSummary)")
            }
        }
    }

    private var stepperStack: some View {
        VStack(spacing: SpotterV2.Spacing.sm) {
            V2TargetStepperRow(
                theme: theme,
                title: "Sets",
                value: draft.draftSetCount,
                rangeText: "\(draft.minSetCount)-\(draft.maxSetCount)",
                canDecrease: draft.draftSetCount > draft.minSetCount,
                canIncrease: draft.draftSetCount < draft.maxSetCount,
                onDecrease: { draft.draftSetCount -= 1 },
                onIncrease: { draft.draftSetCount += 1 }
            )

            if draft.canEditTargetValue,
               let targetValue = draft.draftTargetValue {
                V2TargetStepperRow(
                    theme: theme,
                    title: draft.targetValueLabel,
                    value: targetValue,
                    rangeText: "\(draft.minTargetValue)-\(draft.maxTargetValue)",
                    canDecrease: targetValue > draft.minTargetValue,
                    canIncrease: targetValue < draft.maxTargetValue,
                    onDecrease: {
                        draft.draftTargetValue = max(targetValue - targetStep, draft.minTargetValue)
                    },
                    onIncrease: {
                        draft.draftTargetValue = min(targetValue + targetStep, draft.maxTargetValue)
                    }
                )
            } else {
                V2Card(theme: theme, radius: SpotterV2.Radius.md) {
                    HStack {
                        VStack(alignment: .leading, spacing: SpotterV2.Spacing.xxxs) {
                            Text(draft.targetValueLabel)
                                .font(SpotterV2Typography.caption())
                                .tracking(1.2)
                                .textCase(.uppercase)
                                .foregroundStyle(SpotterV2.Tokens.mutedForeground)
                            Text(draft.draftTarget.formattedText)
                                .font(SpotterV2Typography.heading(size: 20))
                                .foregroundStyle(SpotterV2.Tokens.foreground)
                        }

                        Spacer()

                        V2StatusPill(theme: theme, label: "Sets only")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var messageView: some View {
        if let message = validationMessage, !message.isEmpty {
            Text(message)
                .font(SpotterV2Typography.body(size: 12, weight: .bold))
                .foregroundStyle(SpotterV2.Tokens.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(message)
        }
    }

    private var actionButtons: some View {
        VStack(spacing: SpotterV2.Spacing.sm) {
            V2CTAButton(
                title: "Save Changes",
                systemImage: "checkmark",
                theme: theme
            ) {
                let validation = onSave(draft)
                draft = validation.draft
                validationMessage = validation.message
                if validation.isValid {
                    dismiss()
                }
            }

            V2SecondaryButton(
                title: "Reset to Original Plan",
                systemImage: "arrow.counterclockwise",
                theme: theme
            ) {
                onReset(draft.exerciseId)
                dismiss()
            }
        }
    }

    private var targetSummary: String {
        "\(draft.draftSetCount) x \(draft.draftTarget.formattedText)"
    }

    private var targetStep: Int {
        switch draft.draftTarget {
        case .reps:
            return 1
        case .hold, .timed, .amrap(seconds: .some):
            return 5
        case .amrap(seconds: nil), .open:
            return 1
        }
    }
}

private struct V2TargetStepperRow: View {
    let theme: SpotterThemeOption
    let title: String
    let value: Int
    let rangeText: String
    let canDecrease: Bool
    let canIncrease: Bool
    let onDecrease: () -> Void
    let onIncrease: () -> Void

    var body: some View {
        V2Card(theme: theme, radius: SpotterV2.Radius.md) {
            HStack(spacing: SpotterV2.Spacing.md) {
                VStack(alignment: .leading, spacing: SpotterV2.Spacing.xxxs) {
                    Text(title)
                        .font(SpotterV2Typography.caption())
                        .tracking(1.2)
                        .textCase(.uppercase)
                        .foregroundStyle(SpotterV2.Tokens.mutedForeground)
                    Text("Range \(rangeText)")
                        .font(SpotterV2Typography.caption(weight: .bold))
                        .foregroundStyle(SpotterV2.Tokens.mutedForeground)
                }

                Spacer()

                stepperButton(systemImage: "minus", isEnabled: canDecrease, action: onDecrease)

                Text("\(value)")
                    .font(SpotterV2Typography.mono(size: 30))
                    .monospacedDigit()
                    .foregroundStyle(SpotterV2.Tokens.foreground)
                    .frame(minWidth: 56)
                    .accessibilityLabel("\(title) value \(value)")

                stepperButton(systemImage: "plus", isEnabled: canIncrease, action: onIncrease)
            }
        }
    }

    private func stepperButton(
        systemImage: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .black))
                .foregroundStyle(isEnabled ? .black : SpotterV2.Tokens.mutedForeground)
                .frame(width: 42, height: 42)
                .background(isEnabled ? SpotterV2.Tokens.primary(theme) : SpotterV2.Tokens.secondary)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(systemImage == "plus" ? "Increase \(title)" : "Decrease \(title)")
    }
}

#if DEBUG
private struct V2TargetVolumeEditSheetPreviewContent: View {
    let theme: SpotterThemeOption

    private var draft: TargetVolumeDraft {
        TargetVolumeDraft(
            exerciseId: PlanExerciseIdentifier(blockIndex: 0, exerciseIndex: 0),
            originalExerciseType: .squat,
            draftSetCount: 3,
            draftTarget: .reps(12),
            minSetCount: 1,
            maxSetCount: 5,
            minTargetValue: 4,
            maxTargetValue: 20,
            validationMessage: nil
        )
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            SpotterV2.Tokens.background.ignoresSafeArea()
            V2TargetVolumeEditSheet(
                theme: theme,
                draft: draft,
                onSave: { .accepted($0, didClamp: false, message: nil) },
                onReset: { _ in }
            )
        }
    }
}

private struct V2TargetVolumeEditSheet_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            ForEach(SpotterThemeOption.allCases) { theme in
                V2TargetVolumeEditSheetPreviewContent(theme: theme)
                    .previewDisplayName("\(theme.displayName) - SE")
                    .previewDevice("iPhone SE (3rd generation)")
                V2TargetVolumeEditSheetPreviewContent(theme: theme)
                    .previewDisplayName("\(theme.displayName) - Pro Max")
                    .previewDevice("iPhone 17 Pro Max")
            }
        }
    }
}
#endif
