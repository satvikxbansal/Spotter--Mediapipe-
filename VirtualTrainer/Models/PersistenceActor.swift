import Foundation

nonisolated enum PersistenceWriteOutcome: Equatable {
    case written
    case superseded
}

actor PersistenceActor {
    static let shared = PersistenceActor()

    private struct PendingWriteContinuation {
        let outcomeOnSuccess: PersistenceWriteOutcome
        let continuation: CheckedContinuation<PersistenceWriteOutcome, Error>
    }

    private struct PendingWrite {
        var data: Data
        var options: Data.WritingOptions
        var continuations: [PendingWriteContinuation]
    }

    private var pendingWrites: [URL: PendingWrite] = [:]
    private var activeWriteURLs: Set<URL> = []

    func read(from url: URL) throws -> Data {
        try Data(contentsOf: url)
    }

    func write(_ data: Data, to url: URL, options: Data.WritingOptions) throws {
        try data.write(to: url, options: options)
    }

    func remove(_ url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }

    func createDirectoryIfNeeded(for url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }

    func encode<T: Encodable>(
        _ value: T,
        outputFormatting: JSONEncoder.OutputFormatting = [],
        usesISO8601Dates: Bool = true
    ) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = outputFormatting
        if usesISO8601Dates {
            encoder.dateEncodingStrategy = .iso8601
        }
        return try encoder.encode(value)
    }

    func writeLatest(
        _ data: Data,
        to url: URL,
        options: Data.WritingOptions
    ) async throws -> PersistenceWriteOutcome {
        try await withCheckedThrowingContinuation { continuation in
            enqueueLatestWrite(
                data,
                to: url,
                options: options,
                continuation: continuation
            )
        }
    }

    private func enqueueLatestWrite(
        _ data: Data,
        to url: URL,
        options: Data.WritingOptions,
        continuation: CheckedContinuation<PersistenceWriteOutcome, Error>
    ) {
        let latestContinuation = PendingWriteContinuation(
            outcomeOnSuccess: .written,
            continuation: continuation
        )

        if var pendingWrite = pendingWrites[url] {
            pendingWrite.data = data
            pendingWrite.options = options
            pendingWrite.continuations = pendingWrite.continuations.map {
                PendingWriteContinuation(
                    outcomeOnSuccess: .superseded,
                    continuation: $0.continuation
                )
            }
            pendingWrite.continuations.append(latestContinuation)
            pendingWrites[url] = pendingWrite
        } else {
            pendingWrites[url] = PendingWrite(
                data: data,
                options: options,
                continuations: [latestContinuation]
            )
        }

        guard !activeWriteURLs.contains(url) else { return }
        activeWriteURLs.insert(url)
        Task {
            await self.drainLatestWrites(for: url)
        }
    }

    private func drainLatestWrites(for url: URL) async {
        while true {
            await Task.yield()

            guard let pendingWrite = pendingWrites.removeValue(forKey: url) else {
                activeWriteURLs.remove(url)
                return
            }

            do {
                try createDirectoryIfNeeded(for: url)
                try write(pendingWrite.data, to: url, options: pendingWrite.options)
                pendingWrite.continuations.forEach {
                    $0.continuation.resume(returning: $0.outcomeOnSuccess)
                }
            } catch {
                pendingWrite.continuations.forEach {
                    $0.continuation.resume(throwing: error)
                }
            }
        }
    }
}
