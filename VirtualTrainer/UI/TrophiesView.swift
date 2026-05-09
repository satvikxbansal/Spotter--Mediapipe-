import SwiftUI

struct TrophiesView: View {
    @EnvironmentObject private var calibrationStore: CalibrationStore
    @EnvironmentObject private var historyStore: WorkoutHistoryStore
    @EnvironmentObject private var trophyStore: TrophyStore

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    header
                    featuredSection
                    inProgressSection
                    comingSoonSection

                    NavigationLink {
                        TrophyCollectionView()
                    } label: {
                        Label("View All Trophies", systemImage: "square.grid.2x2.fill")
                    }
                    .buttonStyle(SecondaryCTAStyle())

                    Button {
                    } label: {
                        Label("Share Collection", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(SecondaryCTAStyle())
                    .disabled(true)
                    .opacity(0.45)
                }
                .padding(Theme.Spacing.lg)
                .padding(.bottom, Theme.Spacing.xxxl)
            }
            .background(Theme.Colors.background)
            .navigationTitle("Trophies")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                Task {
                    await refreshProgress()
                }
            }
            .onChange(of: historyStore.summaries) {
                Task {
                    await refreshProgress()
                }
            }
            .onChange(of: calibrationStore.status) {
                Task {
                    await refreshProgress()
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        let earnedCount = trophyStore.snapshot.availableProgress.filter(\.earned).count
        let availableCount = trophyStore.snapshot.availableProgress.count

        return VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Image(systemName: "trophy.fill")
                .font(.system(size: 30, weight: .black))
                .foregroundStyle(Theme.Colors.background)
                .frame(width: 64, height: 64)
                .background(Theme.Colors.accent)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("Trophy Case")
                    .header(size: 40)
                Text("\(earnedCount)/\(availableCount) earned")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(Theme.Colors.textSecondary)
            }

            ProgressView(value: availableCount == 0 ? 0 : Double(earnedCount) / Double(availableCount))
                .tint(Theme.Colors.accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var featuredSection: some View {
        let featured = featuredProgress()
        if !featured.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                TrophySectionHeader(title: "Featured")
                VStack(spacing: Theme.Spacing.sm) {
                    ForEach(featured) { progress in
                        if let definition = TrophyDefinitionCatalog.definition(for: progress.trophyId) {
                            TrophyProgressCard(definition: definition, progress: progress, isFeatured: true)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var inProgressSection: some View {
        let inProgress = trophyStore.snapshot.inProgress
            .filter { $0.confidence != .unavailable }
            .sorted { lhs, rhs in
                if lhs.progressFraction == rhs.progressFraction {
                    return sortOrder(lhs) < sortOrder(rhs)
                }
                return lhs.progressFraction > rhs.progressFraction
            }
            .prefix(6)

        if !inProgress.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                TrophySectionHeader(title: "In Progress")
                VStack(spacing: Theme.Spacing.sm) {
                    ForEach(Array(inProgress)) { progress in
                        if let definition = TrophyDefinitionCatalog.definition(for: progress.trophyId) {
                            TrophyProgressCard(definition: definition, progress: progress)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var comingSoonSection: some View {
        let comingSoon = trophyStore.snapshot.comingSoonProgress
        if !comingSoon.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                TrophySectionHeader(title: "Coming Soon")
                VStack(spacing: Theme.Spacing.sm) {
                    ForEach(comingSoon) { progress in
                        if let definition = TrophyDefinitionCatalog.definition(for: progress.trophyId) {
                            TrophyProgressCard(definition: definition, progress: progress)
                        }
                    }
                }
            }
        }
    }

    private func refreshProgress() async {
        await trophyStore.updateAll(
            history: historyStore.summaries,
            calibrationStatus: calibrationStore.status
        )
    }

    private func featuredProgress() -> [TrophyProgress] {
        let earned = trophyStore.snapshot.earnedProgress
            .filter { TrophyDefinitionCatalog.definition(for: $0.trophyId)?.isComingSoon == false }
            .sorted { sortOrder($0) < sortOrder($1) }

        if !earned.isEmpty {
            return Array(earned.suffix(2))
        }

        return Array(
            trophyStore.snapshot.inProgress
                .filter { $0.confidence != .unavailable }
                .sorted {
                    if $0.progressFraction == $1.progressFraction {
                        return sortOrder($0) < sortOrder($1)
                    }
                    return $0.progressFraction > $1.progressFraction
                }
                .prefix(2)
        )
    }

    private func sortOrder(_ progress: TrophyProgress) -> Int {
        TrophyDefinitionCatalog.definition(for: progress.trophyId)?.sortOrder ?? Int.max
    }
}

struct TrophyCollectionView: View {
    @EnvironmentObject private var trophyStore: TrophyStore

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                Text("All Trophies")
                    .header(size: 34)

                VStack(spacing: Theme.Spacing.sm) {
                    ForEach(trophyStore.snapshot.progress) { progress in
                        if let definition = TrophyDefinitionCatalog.definition(for: progress.trophyId) {
                            TrophyProgressCard(definition: definition, progress: progress)
                        }
                    }
                }

                Button {
                } label: {
                    Label("Share Collection", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(SecondaryCTAStyle())
                .disabled(true)
                .opacity(0.45)
            }
            .padding(Theme.Spacing.lg)
            .padding(.bottom, Theme.Spacing.xxxl)
        }
        .background(Theme.Colors.background)
        .navigationTitle("Collection")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
    }
}

struct TrophyProgressCard: View {
    let definition: TrophyDefinition
    let progress: TrophyProgress
    var isFeatured: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                Image(systemName: definition.iconName)
                    .font(.system(size: isFeatured ? 26 : 20, weight: .black))
                    .foregroundStyle(iconForeground)
                    .frame(width: isFeatured ? 58 : 46, height: isFeatured ? 58 : 46)
                    .background(iconBackground)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))

                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    HStack(spacing: Theme.Spacing.xs) {
                        Text(definition.title)
                            .font(.system(size: isFeatured ? 20 : 16, weight: .black))
                            .textCase(.uppercase)
                            .foregroundStyle(titleColor)
                            .fixedSize(horizontal: false, vertical: true)

                        Spacer(minLength: Theme.Spacing.sm)

                        TrophyStatusBadge(text: statusText, isComingSoon: definition.isComingSoon)
                    }

                    Text(definition.subtitle)
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !definition.isComingSoon {
                ProgressView(value: progress.progressFraction)
                    .tint(progress.earned ? Theme.Colors.positive : Theme.Colors.accent)
            }

            HStack(spacing: Theme.Spacing.xs) {
                Text(progress.progressLabel)
                if progress.confidence == .estimated {
                    Text("Estimated")
                }
            }
            .font(.system(size: 11, weight: .black))
            .textCase(.uppercase)
            .foregroundStyle(definition.isComingSoon ? Theme.Colors.textTertiary : Theme.Colors.textSecondary)
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .stroke(borderColor, lineWidth: 1)
        )
        .opacity(definition.isComingSoon ? 0.58 : 1)
    }

    private var statusText: String {
        if definition.isComingSoon { return "Soon" }
        if progress.earned { return "Earned" }
        return definition.rarity.displayName
    }

    private var titleColor: Color {
        if definition.isComingSoon { return Theme.Colors.textTertiary }
        if progress.earned { return Theme.Colors.accent }
        return Theme.Colors.textPrimary
    }

    private var iconForeground: Color {
        definition.isComingSoon ? Theme.Colors.textSecondary : Theme.Colors.background
    }

    private var iconBackground: Color {
        if definition.isComingSoon { return Theme.Colors.surfaceRaised }
        if progress.earned { return Theme.Colors.accent }
        return Theme.Colors.accentMuted
    }

    private var borderColor: Color {
        if definition.isComingSoon { return Theme.Colors.divider }
        if progress.earned { return Theme.Colors.accent.opacity(0.45) }
        return Theme.Colors.divider
    }
}

private struct TrophySectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 18, weight: .black))
            .textCase(.uppercase)
            .foregroundStyle(Theme.Colors.textPrimary)
    }
}

private struct TrophyStatusBadge: View {
    let text: String
    let isComingSoon: Bool

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .black))
            .textCase(.uppercase)
            .foregroundStyle(isComingSoon ? Theme.Colors.textSecondary : Theme.Colors.background)
            .padding(.horizontal, Theme.Spacing.xs)
            .padding(.vertical, Theme.Spacing.xxxs)
            .background(isComingSoon ? Theme.Colors.surfaceRaised : Theme.Colors.accent)
            .clipShape(Capsule())
    }
}

#Preview {
    TrophiesView()
        .environmentObject(CalibrationStore())
        .environmentObject(WorkoutHistoryStore())
        .environmentObject(TrophyStore())
}
