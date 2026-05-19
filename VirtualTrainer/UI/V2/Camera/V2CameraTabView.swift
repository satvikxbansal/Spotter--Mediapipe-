import SwiftUI

nonisolated enum V2ExerciseFilterCategory: String, CaseIterable, Identifiable, Equatable {
    case upper
    case lower
    case core
    case cardio
    case yoga
    case mobility

    var id: String { rawValue }

    var title: String {
        switch self {
        case .upper:
            return "Upper Body"
        case .lower:
            return "Lower Body"
        case .core:
            return "Core"
        case .cardio:
            return "Cardio"
        case .yoga:
            return "Yoga"
        case .mobility:
            return "Mobility"
        }
    }

    func matches(_ metadata: ExercisePlanMetadata) -> Bool {
        switch self {
        case .upper:
            return metadata.bodyRegion == .upper
        case .lower:
            return metadata.bodyRegion == .lower
        case .core:
            return metadata.bodyRegion == .core ||
                [.coreAntiExtension, .coreFlexion, .coreRotation].contains(metadata.movementPattern)
        case .cardio:
            return metadata.movementPattern == .cardio
        case .yoga:
            return metadata.movementPattern == .yogaHold
        case .mobility:
            return metadata.bodyRegion == .mobility &&
                metadata.movementPattern != .yogaHold &&
                metadata.movementPattern != .cardio
        }
    }
}

struct V2CameraTabView: View {
    @EnvironmentObject private var onboardingStore: OnboardingStore
    @EnvironmentObject private var themeStore: ThemeStore

    @State private var searchText = ""
    @State private var selectedCategory: V2ExerciseFilterCategory = .upper
    @State private var selectedExercise: ExerciseType?
    @State private var summary: FreeAnalysisSummary?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                GeometryReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: SpotterV2.Spacing.xl) {
                            header
                            searchField
                            categoryStrip
                            exerciseList
                        }
                        .frame(
                            width: Swift.max(0, proxy.size.width - SpotterV2.Spacing.xl * 2),
                            alignment: .leading
                        )
                        .padding(.horizontal, SpotterV2.Spacing.xl)
                        .padding(.top, SpotterV2.Spacing.xl)
                        .padding(.bottom, 132)
                    }
                }
            }
            .background(SpotterV2.Tokens.background)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(item: $selectedExercise) { exerciseType in
                let launchConfiguration = FreeAnalysisCameraLaunchConfiguration.make(
                    exerciseType: exerciseType,
                    profile: onboardingStore.profile
                )
                CameraReadinessView(
                    exerciseType: launchConfiguration.exerciseType,
                    coach: launchConfiguration.coach,
                    onSummary: { summary = $0 }
                )
            }
            .sheet(item: $summary) { summary in
                FreeAnalysisSummaryView(summary: summary)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
        .preferredColorScheme(.dark)
        .accessibilityIdentifier("V2CameraTabView")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: SpotterV2.Spacing.sm) {
            Text("Quick Start")
                .font(SpotterV2Typography.caption())
                .tracking(1.6)
                .textCase(.uppercase)
                .foregroundStyle(SpotterV2.Tokens.mutedForeground)

            Text("Form Check")
                .font(SpotterV2Typography.display(size: 46))
                .fontWidth(.compressed)
                .italic()
                .textCase(.uppercase)
                .foregroundStyle(SpotterV2.Tokens.foreground)
                .lineLimit(1)
                .minimumScaleFactor(0.56)

        }
        .accessibilityElement(children: .combine)
    }

    private var searchField: some View {
        HStack(spacing: SpotterV2.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18, weight: .black))
                .foregroundStyle(SpotterV2.Tokens.mutedForeground)

            TextField("SEARCH EXERCISES...", text: $searchText)
                .font(SpotterV2Typography.heading(size: 12))
                .fontWidth(.compressed)
                .tracking(1.0)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .foregroundStyle(SpotterV2.Tokens.foreground)
                .submitLabel(.search)
        }
        .padding(.horizontal, SpotterV2.Spacing.lg)
        .frame(minHeight: 56)
        .background(SpotterV2.Tokens.card)
        .clipShape(RoundedRectangle(cornerRadius: SpotterV2.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: SpotterV2.Radius.lg)
                .stroke(SpotterV2.Tokens.border, lineWidth: SpotterV2.BorderWidth.standard)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Search exercises")
    }

    private var categoryStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: SpotterV2.Spacing.sm) {
                ForEach(V2ExerciseFilterCategory.allCases) { category in
                    Button {
                        HapticsEngine.shared.buttonTap()
                        selectedCategory = category
                    } label: {
                        V2ExerciseCategoryChip(
                            theme: themeStore.selectedTheme,
                            title: category.title,
                            count: exercises(in: category, applyingSearch: false).count,
                            isSelected: selectedCategory == category
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(category.title)
                    .accessibilityValue(selectedCategory == category ? "Selected" : "")
                }
            }
            .padding(.bottom, SpotterV2.Spacing.xxs)
        }
    }

    @ViewBuilder
    private var exerciseList: some View {
        let exercises = exercises(in: selectedCategory, applyingSearch: true)
        if exercises.isEmpty {
            V2EmptyState(
                theme: themeStore.selectedTheme,
                title: "No matches",
                bodyText: "Try another category or clear the search field.",
                ctaTitle: nil,
                ctaAction: nil
            )
            .padding(.top, SpotterV2.Spacing.lg)
        } else {
            VStack(spacing: SpotterV2.Spacing.sm) {
                ForEach(Array(exercises.enumerated()), id: \.element.exerciseType) { index, metadata in
                    Button {
                        HapticsEngine.shared.buttonTap()
                        selectedExercise = metadata.exerciseType
                    } label: {
                        V2ExerciseRow(
                            theme: themeStore.selectedTheme,
                            index: index + 1,
                            name: metadata.exerciseType.displayName,
                            target: metadata.difficulty?.v2DisplayName ?? "Free",
                            subtitle: metadata.v2Subtitle,
                            ctaTitle: "Train Free",
                            systemImage: "play.fill"
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Train free \(metadata.exerciseType.displayName)")
                    .accessibilityHint(metadata.exerciseType.visibilityHint)
                }
            }
        }
    }

    private func exercises(
        in category: V2ExerciseFilterCategory,
        applyingSearch: Bool
    ) -> [ExercisePlanMetadata] {
        let query = applyingSearch
            ? searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            : ""
        return ExerciseMetadataCatalog.freeAnalysisMetadata
            .filter { category.matches($0) }
            .filter { metadata in
                guard !query.isEmpty else { return true }
                return metadata.exerciseType.displayName.localizedCaseInsensitiveContains(query)
            }
            .sorted {
                $0.exerciseType.displayName.localizedCaseInsensitiveCompare($1.exerciseType.displayName) == .orderedAscending
            }
    }
}

private struct V2ExerciseCategoryChip: View {
    let theme: SpotterThemeOption
    let title: String
    let count: Int
    let isSelected: Bool

    var body: some View {
        HStack(spacing: SpotterV2.Spacing.xs) {
            Text(title)
                .font(SpotterV2Typography.heading(size: 10))
                .fontWidth(.compressed)
                .italic()
                .textCase(.uppercase)
                .foregroundStyle(isSelected ? SpotterV2.Tokens.primary(theme) : SpotterV2.Tokens.mutedForeground)

            Text("\(count)")
                .font(SpotterV2Typography.caption())
                .foregroundStyle(isSelected ? .black : SpotterV2.Tokens.mutedForeground)
                .padding(.horizontal, SpotterV2.Spacing.xs)
                .padding(.vertical, SpotterV2.Spacing.xxxs)
                .background(isSelected ? SpotterV2.Tokens.primary(theme) : SpotterV2.Tokens.foreground.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: SpotterV2.Radius.xs))
        }
        .padding(.horizontal, SpotterV2.Spacing.sm)
        .padding(.vertical, SpotterV2.Spacing.xs)
        .background(SpotterV2.Tokens.card)
        .clipShape(RoundedRectangle(cornerRadius: SpotterV2.Radius.xs))
        .overlay(
            RoundedRectangle(cornerRadius: SpotterV2.Radius.xs)
                .stroke(
                    isSelected ? SpotterV2.Tokens.primary(theme) : SpotterV2.Tokens.border,
                    lineWidth: SpotterV2.BorderWidth.standard
                )
        )
        .background(alignment: .topLeading) {
            if isSelected {
                RoundedRectangle(cornerRadius: SpotterV2.Radius.xs)
                    .fill(SpotterV2.Tokens.primary(theme).opacity(0.1))
                    .offset(x: 3, y: 3)
            }
        }
    }
}

private extension ExerciseDifficulty {
    var v2DisplayName: String {
        rawValue.capitalized
    }
}

private extension ExercisePlanMetadata {
    var v2Subtitle: String {
        let region: String
        switch bodyRegion {
        case .upper:
            region = "Upper body"
        case .lower:
            region = "Lower body"
        case .core:
            region = "Core"
        case .fullBody:
            region = "Full body"
        case .mobility:
            region = "Mobility"
        }

        let pattern: String
        switch movementPattern {
        case .squat:
            pattern = "Squat pattern"
        case .hinge:
            pattern = "Hinge pattern"
        case .lunge:
            pattern = "Lunge pattern"
        case .push:
            pattern = "Push pattern"
        case .pull:
            pattern = "Pull pattern"
        case .carry:
            pattern = "Carry pattern"
        case .coreFlexion:
            pattern = "Core flexion"
        case .coreAntiExtension:
            pattern = "Anti-extension"
        case .coreRotation:
            pattern = "Core rotation"
        case .balance:
            pattern = "Balance"
        case .mobility:
            pattern = "Mobility"
        case .cardio:
            pattern = "Cardio"
        case .yogaHold:
            pattern = "Yoga hold"
        }

        return "\(region) • \(pattern)"
    }
}

#if DEBUG
private struct V2CameraTabView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            ForEach(SpotterThemeOption.allCases) { theme in
                V2CameraTabPreviewHost(theme: theme)
                    .previewDisplayName("\(theme.displayName) Camera SE")
                    .previewDevice("iPhone SE (3rd generation)")
                V2CameraTabPreviewHost(theme: theme)
                    .previewDisplayName("\(theme.displayName) Camera Pro Max")
                    .previewDevice("iPhone 17 Pro Max")
            }
        }
    }
}

private struct V2CameraTabPreviewHost: View {
    let theme: SpotterThemeOption
    @StateObject private var onboardingStore: OnboardingStore
    @StateObject private var themeStore: ThemeStore
    @StateObject private var calibrationStore = CalibrationStore()
    @StateObject private var historyStore = WorkoutHistoryStore()
    @StateObject private var trophyStore = TrophyStore()
    @StateObject private var appDependencies = AppDependencies.local()
    @StateObject private var designToggle = DesignSystemV2ToggleStore(remoteFlagSnapshotProvider: { true })
    @State private var appPresentation = AppLevelPresentationState()

    init(theme: SpotterThemeOption) {
        self.theme = theme
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("V2CameraTabPreview-\(UUID().uuidString)", isDirectory: true)
        _onboardingStore = StateObject(
            wrappedValue: OnboardingStore(fileURL: directory.appendingPathComponent("UserProfile.json"))
        )
        _themeStore = StateObject(
            wrappedValue: ThemeStore(fileURL: directory.appendingPathComponent("Theme.json"), defaultTheme: theme)
        )
    }

    var body: some View {
        V2CameraTabView()
            .environmentObject(onboardingStore)
            .environmentObject(themeStore)
            .environmentObject(calibrationStore)
            .environmentObject(historyStore)
            .environmentObject(trophyStore)
            .environmentObject(appDependencies)
            .environmentObject(designToggle)
            .environment(\.appLevelPresenter, $appPresentation)
            .task {
                if onboardingStore.profile == nil {
                    _ = await onboardingStore.saveProfile(Self.profile(theme: theme))
                }
            }
    }

    private static func profile(theme: SpotterThemeOption) -> UserProfile {
        let now = Date()
        return UserProfile(
            id: UUID(),
            displayName: "Satvik Bansal",
            genderIdentity: .male,
            age: 30,
            height: 178,
            heightUnit: .metric,
            weight: 84,
            weightUnit: .metric,
            primaryGoal: .strength,
            fitnessLevel: .intermediate,
            equipment: [.bodyweight, .dumbbells, .mat, .wall],
            preferredCoach: .bennett,
            selectedTheme: theme,
            onboardingCompletedAt: now,
            createdAt: now,
            updatedAt: now
        )
    }
}
#endif
