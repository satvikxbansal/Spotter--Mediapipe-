import Foundation
import Combine

@MainActor
final class ThemeStore: ObservableObject {
    @Published private(set) var selectedTheme: SpotterThemeOption
    @Published var persistenceError: String?

    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(fileURL: URL? = nil, defaultTheme: SpotterThemeOption = .hyper) {
        self.fileURL = fileURL ?? Self.defaultThemeURL()
        self.selectedTheme = defaultTheme
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        loadTheme()
    }

    @discardableResult
    func updateSelectedTheme(_ theme: SpotterThemeOption) -> Bool {
        let previousTheme = selectedTheme
        let shouldPersist = selectedTheme != theme ||
            persistenceError != nil ||
            !FileManager.default.fileExists(atPath: fileURL.path)

        guard shouldPersist else { return true }

        selectedTheme = theme
        guard persist() else {
            selectedTheme = previousTheme
            return false
        }
        return true
    }

    @discardableResult
    func sync(with profile: UserProfile?) -> Bool {
        guard let profile else { return true }
        return updateSelectedTheme(profile.selectedTheme)
    }

    func reload() {
        loadTheme()
    }

    private func loadTheme() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            persistenceError = nil
            return
        }

        do {
            let data = try Data(contentsOf: fileURL)
            if let envelope = try? decoder.decode(ThemeEnvelope.self, from: data) {
                selectedTheme = envelope.selectedTheme
            } else {
                selectedTheme = try decoder.decode(SpotterThemeOption.self, from: data)
            }
            persistenceError = nil
        } catch {
            persistenceError = "Could not load theme: \(error.localizedDescription)"
        }
    }

    @discardableResult
    private func persist() -> Bool {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try encoder.encode(ThemeEnvelope(selectedTheme: selectedTheme))
            try data.write(to: fileURL, options: [.atomic])
            persistenceError = nil
            return true
        } catch {
            persistenceError = "Could not save theme: \(error.localizedDescription)"
            return false
        }
    }

    private static func defaultThemeURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("Spotter", isDirectory: true)
            .appendingPathComponent("Theme.json")
    }
}

private struct ThemeEnvelope: Codable {
    let selectedTheme: SpotterThemeOption
}
