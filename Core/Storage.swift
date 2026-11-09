import Foundation

struct SavedState: Codable, Equatable {
    var defaults = Preferences()
    var defaultDays: Set<Int> = []
    var plans: [Plan] = []
    var ledger: [Signal] = []
    var challenges: [Challenge] = []
    var completed: Set<Occurrence> = []
    var lastProblem: Problem?
}

struct Storage {
    let url: URL
    func read() throws -> SavedState {
        guard FileManager.default.fileExists(atPath: url.path) else { return SavedState() }
        return try JSONDecoder().decode(SavedState.self, from: Data(contentsOf: url))
    }
    func write(_ value: SavedState) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(value).write(to: url, options: .atomic)
    }
}

