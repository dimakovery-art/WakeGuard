import Foundation

struct Problem: Codable, Equatable {
    var a: Int
    var b: Int
    var operation: String
    var result: Int {
        switch operation { case "+": return a + b; case "−": return a - b; default: return a * b }
    }
    var text: String { "\(a) \(operation) \(b)" }
    static func draw(_ level: Difficulty, excluding previous: Problem?) -> Problem {
        var next: Problem
        repeat {
            switch level {
            case .easy:
                next = Problem(a: .random(in: 1...9), b: .random(in: 1...9), operation: "+")
            case .medium:
                let a = Int.random(in: 10...99), b = Int.random(in: 10...99)
                next = Problem(a: max(a, b), b: min(a, b), operation: Bool.random() ? "+" : "−")
            case .hard:
                next = Bool.random() ? Problem(a: .random(in: 11...24), b: .random(in: 3...9), operation: "×")
                                     : Problem(a: .random(in: 101...299), b: .random(in: 27...99), operation: "−")
            }
        } while next == previous
        return next
    }
}

struct Challenge: Identifiable, Codable, Equatable {
    var id: Occurrence { occurrence }
    var occurrence: Occurrence
    var level: Difficulty
    var total: Int
    var solved = 0
    var problem: Problem
    var input = ""
    var incorrect = false
    mutating func submit() -> Bool {
        guard Int(input) == problem.result else { incorrect = true; return false }
        solved += 1
        input = ""
        incorrect = false
        if solved < total { problem = .draw(level, excluding: problem) }
        return true
    }
}

