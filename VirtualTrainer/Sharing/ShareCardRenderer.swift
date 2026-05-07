import SwiftUI
import UIKit

@MainActor
struct ShareCardRenderer {
    func renderTrainingHeatmapPoster(
        summariesByDay: [Date: DayIntensitySummary],
        profile: UserProfile,
        accent: Color,
        now: Date = Date()
    ) -> UIImage? {
        let view = TrainingHeatmapPosterView(
            summaries: summariesByDay.values.sorted { $0.date < $1.date },
            profile: profile,
            accent: accent,
            generatedAt: now
        )
        .frame(width: 1080, height: 1920)

        let renderer = ImageRenderer(content: view)
        renderer.proposedSize = ProposedViewSize(width: 1080, height: 1920)
        renderer.scale = 1
        return renderer.uiImage
    }
}

private struct TrainingHeatmapPosterView: View {
    let summaries: [DayIntensitySummary]
    let profile: UserProfile
    let accent: Color
    let generatedAt: Date

    private let rows = 7
    private let columns = 12

    var body: some View {
        ZStack {
            Theme.Colors.background
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 54) {
                VStack(alignment: .leading, spacing: 18) {
                    Text(profile.displayName ?? "Spotter Athlete")
                        .font(.system(size: 78, weight: .black, design: .rounded))
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.72)

                    Text("12-week training heatmap")
                        .font(.system(size: 30, weight: .black))
                        .tracking(2.4)
                        .textCase(.uppercase)
                        .foregroundStyle(accent)
                }

                VStack(alignment: .leading, spacing: 30) {
                    heatmap

                    HStack(spacing: 18) {
                        posterStat(value: "\(activeDays)", label: "active days")
                        posterStat(value: "\(workoutCount)", label: "workouts")
                        posterStat(value: formText, label: "avg form")
                    }
                }
                .padding(42)
                .background(Theme.Colors.surface)
                .clipShape(RoundedRectangle(cornerRadius: 28))

                Spacer()

                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Train with me on Spotter")
                            .font(.system(size: 34, weight: .black))
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Text(dateText)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }

                    Spacer()

                    Text("SPOTTER")
                        .font(.system(size: 28, weight: .black))
                        .tracking(3)
                        .foregroundStyle(Theme.Colors.background)
                        .padding(.horizontal, 26)
                        .padding(.vertical, 16)
                        .background(accent)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
            }
            .padding(.horizontal, 76)
            .padding(.top, 112)
            .padding(.bottom, 92)
        }
    }

    private var heatmap: some View {
        VStack(spacing: 12) {
            ForEach(0..<rows, id: \.self) { row in
                HStack(spacing: 12) {
                    ForEach(0..<columns, id: \.self) { column in
                        RoundedRectangle(cornerRadius: 9)
                            .fill(fillColor(for: daySummary(row: row, column: column).intensity))
                            .frame(width: 66, height: 66)
                            .shadow(
                                color: daySummary(row: row, column: column).intensity >= 4
                                    ? accent.opacity(0.5)
                                    : .clear,
                                radius: 18
                            )
                    }
                }
            }
        }
    }

    private func posterStat(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value)
                .font(.system(size: 48, weight: .black, design: .rounded))
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 18, weight: .black))
                .tracking(1.6)
                .textCase(.uppercase)
                .foregroundStyle(Theme.Colors.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var activeDays: Int {
        summaries.filter { $0.workoutCount > 0 }.count
    }

    private var workoutCount: Int {
        summaries.reduce(0) { $0 + $1.workoutCount }
    }

    private var formText: String {
        let values = summaries.compactMap(\.averageFormScore)
        guard !values.isEmpty else { return "N/A" }
        let average = values.reduce(0, +) / Double(values.count)
        return "\(Int(average.rounded()))%"
    }

    private var dateText: String {
        let formatter = DateFormatter()
        formatter.calendar = TrendEngine().calendar(for: profile)
        formatter.timeZone = formatter.calendar.timeZone
        formatter.dateFormat = "MMMM d, yyyy"
        return formatter.string(from: generatedAt)
    }

    private func daySummary(row: Int, column: Int) -> DayIntensitySummary {
        let index = column * rows + row
        if summaries.indices.contains(index) {
            return summaries[index]
        }
        return DayIntensitySummary(
            date: generatedAt,
            workoutCount: 0,
            totalReps: 0,
            totalHoldSeconds: 0,
            averageFormScore: nil,
            sessions: []
        )
    }

    private func fillColor(for intensity: Int) -> Color {
        switch intensity {
        case 1:
            return accent.opacity(0.24)
        case 2:
            return accent.opacity(0.52)
        case 3:
            return accent.opacity(0.86)
        case 4...:
            return accent
        default:
            return Theme.Colors.surfaceRaised.opacity(0.65)
        }
    }
}
