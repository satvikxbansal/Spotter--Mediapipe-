import SwiftUI

struct TargetVolumeEditSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: TargetVolumeDraft
    @State private var message: String?

    let onSave: (TargetVolumeDraft) -> TargetVolumeValidation
    let onReset: (PlanExerciseIdentifier) -> Void

    init(
        draft: TargetVolumeDraft,
        onSave: @escaping (TargetVolumeDraft) -> TargetVolumeValidation,
        onReset: @escaping (PlanExerciseIdentifier) -> Void
    ) {
        _draft = State(initialValue: draft)
        _message = State(initialValue: draft.validationMessage)
        self.onSave = onSave
        self.onReset = onReset
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                header
                targetVolumeControls
                Spacer(minLength: Theme.Spacing.md)
                actions
            }
            .padding(Theme.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.Colors.background)
            .navigationTitle("Adjust Movement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(draft.originalExerciseType.displayName)
                .font(.system(size: 26, weight: .heavy))
                .foregroundStyle(Theme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text("Target volume")
                .font(.system(size: 13, weight: .black))
                .tracking(0.8)
                .textCase(.uppercase)
                .foregroundStyle(Theme.Colors.accent)
        }
    }

    private var targetVolumeControls: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            controlRow(
                title: "Sets",
                valueText: "\(draft.draftSetCount)",
                stepper: Stepper(
                    "",
                    value: $draft.draftSetCount,
                    in: draft.minSetCount...draft.maxSetCount
                )
                .labelsHidden()
            )

            if draft.canEditTargetValue {
                controlRow(
                    title: draft.targetValueLabel,
                    valueText: "\(draft.draftTargetValue ?? draft.minTargetValue)",
                    stepper: Stepper(
                        "",
                        value: targetValueBinding,
                        in: draft.minTargetValue...draft.maxTargetValue
                    )
                    .labelsHidden()
                )
            } else {
                HStack {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xxxs) {
                        Text(draft.targetValueLabel)
                            .font(.system(size: 15, weight: .heavy))
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Text(draft.draftTarget.formattedText)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    Spacer()
                }
                .padding(Theme.Spacing.md)
                .background(Theme.Colors.surface)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
            }

            if let message {
                Text(message)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func controlRow<StepperContent: View>(
        title: String,
        valueText: String,
        stepper: StepperContent
    ) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxxs) {
                Text(title)
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(valueText)
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.Colors.accent)
            }

            Spacer()
            stepper
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
    }

    private var actions: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Button {
                let validation = onSave(draft)
                draft = validation.draft
                message = validation.message
                if validation.isValid {
                    dismiss()
                }
            } label: {
                Text("Save Changes")
            }
            .buttonStyle(PrimaryCTAStyle())

            Button {
                onReset(draft.exerciseId)
                dismiss()
            } label: {
                Text("Reset to Original Plan")
                    .font(.system(size: 13, weight: .black))
                    .tracking(0.8)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Spacing.sm)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Restores this movement to the original plan prescription")
        }
    }

    private var targetValueBinding: Binding<Int> {
        Binding(
            get: {
                draft.draftTargetValue ?? draft.minTargetValue
            },
            set: { newValue in
                draft.draftTargetValue = newValue
            }
        )
    }
}
