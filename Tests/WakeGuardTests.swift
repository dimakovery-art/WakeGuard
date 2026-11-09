import Foundation
import XCTest
@testable import WakeGuard

final class WakeGuardTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }
    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    func testStandardExampleAndAllMinuteLengths() {
        XCTAssertEqual(Schedule.offsets(duration: 30, mode: .standard), [0, 10, 20, 25, 28, 30])
        for length in 1..<1440 {
            for mode in WakeMode.allCases {
                let values = Schedule.offsets(duration: length, mode: mode)
                XCTAssertEqual(values.first, 0)
                XCTAssertEqual(values.last, length)
                XCTAssertEqual(values, Set(values).sorted())
            }
        }
        XCTAssertEqual(Schedule.evenly(1, count: 16), [0, 1])
        XCTAssertEqual(Schedule.evenly(10, count: 4), [0, 3, 6, 10])
    }

    func testMidnightUsesDayOfFinalAndKeepsDistinctIDs() {
        var plan = Plan()
        plan.days = [2]
        plan.start = 23 * 60 + 55
        plan.finish = 5
        let all = Schedule.signals(plan, defaults: Preferences(), now: date(8, 18), completed: [], calendar: calendar)
        let first = all.first { $0.offset == -10 }
        XCTAssertEqual(first?.days, [1])
        XCTAssertEqual(first?.minute, 1435)
        XCTAssertEqual(all.first { $0.offset == 0 }?.days, [2])
        XCTAssertEqual(Set(all.map(\.id)).count, all.count)
        XCTAssertEqual(Schedule.shiftedDays([7], by: 1), [1])
    }

    func testOneTimeSelectsNextFullWindowAndDoesNotRollAfterFiring() throws {
        var plan = Plan()
        plan.start = 1435
        plan.finish = 5
        let now = date(8, 23, 50)
        plan.oneTimeFinal = try Schedule.nextOneTime(plan, now: now, calendar: calendar)
        XCTAssertEqual(plan.oneTimeFinal, date(9, 0, 5))
        let initial = Schedule.signals(plan, defaults: Preferences(), now: now, completed: [], calendar: calendar)
        XCTAssertEqual(initial.first?.fire, date(8, 23, 55))
        XCTAssertTrue(initial.allSatisfy(\.days.isEmpty))
        XCTAssertTrue(Schedule.signals(plan, defaults: Preferences(), now: date(9, 12), completed: [], calendar: calendar).isEmpty)
        XCTAssertEqual(try Schedule.nextOneTime(plan, now: date(8, 23, 58), calendar: calendar), date(10, 0, 5))
    }

    func testConfirmationOnlyRemovesReservesOfOneOccurrence() {
        var plan = Plan()
        plan.days = Set(1...7)
        let key = Occurrence(planID: plan.id, final: date(9, 9))
        let now = date(9, 9, 1)
        func signals(_ plan: Plan, done: Set<Occurrence>) -> [Signal] {
            Schedule.signals(plan, defaults: Preferences(), now: now, completed: done, calendar: calendar)
        }
        let before = signals(plan, done: [])
        XCTAssertEqual(before.filter { $0.occurrence == key }.count, 2)
        let after = signals(plan, done: [key])
        XCTAssertFalse(after.contains { $0.occurrence == key })
        XCTAssertTrue(after.contains { $0.occurrence?.final == date(10, 9) })
        XCTAssertEqual(after.filter { $0.fire == nil }.count, 6)
        var other = plan
        other.id = UUID()
        XCTAssertEqual(signals(other, done: [key]).count, before.count)
    }

    func testDSTAndLocalWeeklyTime() {
        var ny = calendar
        ny.timeZone = TimeZone(identifier: "America/New_York")!
        var plan = Plan()
        plan.days = Set(1...7)
        let start = ny.date(from: DateComponents(year: 2026, month: 3, day: 7, hour: 7))!
        let dates = Schedule.finals(plan, after: start, count: 3, calendar: ny)
        XCTAssertEqual(dates.map { ny.component(.hour, from: $0) }, [9, 9, 9])
        XCTAssertEqual(dates[1].timeIntervalSince(dates[0]), 23 * 3600)
    }

    func testOverridesAndIdempotentRequestComparison() {
        var plan = Plan()
        var prefs = Preferences()
        prefs.mode = .insistent
        prefs.count = 3
        prefs.snooze = 9
        plan.options = prefs
        plan.manual = [0, 15, 30]
        plan.days = [1, 7]
        func queue() -> [Signal] {
            Schedule.signals(plan, defaults: Preferences(), now: date(6, 20), completed: [], calendar: calendar)
        }
        let a = queue(), b = queue()
        XCTAssertEqual(a.filter { $0.fire == nil }.count, 3)
        XCTAssertEqual(a.filter { $0.offset > 0 }.count, 9)
        XCTAssertTrue(zip(a, b).allSatisfy { $0.0.sameRequest(as: $0.1) })
        XCTAssertEqual(a.first?.options.snooze, 9)
        XCTAssertEqual(a.first { $0.offset == 0 }?.soundFile, "rise.wav")
        plan.enabled = false
        XCTAssertTrue(queue().isEmpty)
    }

    func testMathRejectsWrongAnswerAndAdvancesOnce() {
        let key = Occurrence(planID: UUID(), final: date(9, 9))
        var task = Challenge(occurrence: key, level: .medium, total: 2, problem: Problem(a: 38, b: 27, operation: "+"))
        task.input = "64"
        XCTAssertFalse(task.submit())
        XCTAssertTrue(task.incorrect)
        XCTAssertEqual(task.solved, 0)
        let previous = task.problem
        task.input = "65"
        XCTAssertTrue(task.submit())
        XCTAssertNotEqual(task.problem, previous)
        XCTAssertEqual(task.solved, 1)
        task.input = String(task.problem.result)
        XCTAssertTrue(task.submit())
        XCTAssertEqual(task.solved, task.total)
        for level in Difficulty.allCases {
            var p = Problem.draw(level, excluding: nil)
            for _ in 0..<100 {
                let n = Problem.draw(level, excluding: p)
                XCTAssertNotEqual(p, n)
                XCTAssertGreaterThanOrEqual(n.result, 0)
                p = n
            }
        }
    }

    func testAtomicRoundTripAndCorruptFileIsNotReset() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let disk = Storage(url: folder.appendingPathComponent("state.json"))
        var state = try disk.read()
        state.defaults.snooze = 5
        state.defaultDays = [2, 3]
        state.plans = [Plan()]
        let key = Occurrence(planID: state.plans[0].id, final: date(9, 9))
        state.challenges = [Challenge(occurrence: key, level: .hard, total: 3, solved: 1,
                                     problem: Problem(a: 12, b: 7, operation: "×"), input: "8")]
        try disk.write(state)
        XCTAssertEqual(try disk.read(), state)
        let broken = Data("x".utf8)
        try broken.write(to: disk.url)
        XCTAssertThrowsError(try disk.read())
        XCTAssertEqual(try Data(contentsOf: disk.url), broken)
    }
}

