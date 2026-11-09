import Foundation

enum Schedule {
    static func evenly(_ duration: Int, count: Int) -> [Int] {
        guard duration > 0 else { return [0] }
        let n = min(duration + 1, max(2, count))
        return (0..<n).map { $0 * duration / (n - 1) }
    }

    static func offsets(duration: Int, mode: WakeMode) -> [Int] {
        guard duration > 0 else { return [0] }
        if mode == .gentle { return evenly(duration, count: duration >= 8 ? 3 : 2) }
        var leads = [duration, 10, 5, 2, 0]
        if duration >= 20 { leads.append(duration * 2 / 3) }
        if mode == .insistent { leads += [duration * 4 / 5, 7, 3, 1] }
        return Set(leads.filter { $0 <= duration }.map { duration - $0 }).sorted()
    }

    static func clock(on day: Date, minute: Int, calendar: Calendar) -> Date? {
        calendar.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: day,
                      matchingPolicy: .nextTime, repeatedTimePolicy: .first, direction: .forward)
    }

    static func shiftedDays(_ days: Set<Int>, by offset: Int) -> Set<Int> {
        Set(days.map { (($0 - 1 + offset + 7) % 7) + 1 })
    }

    static func finals(_ plan: Plan, after date: Date, count: Int, calendar: Calendar) -> [Date] {
        guard !plan.days.isEmpty else {
            return [plan.oneTimeFinal].compactMap { $0 }.filter { $0 > date }
        }
        var dates: [Date] = []
        let day = calendar.startOfDay(for: date)
        for index in 0...(7 * count) {
            guard let candidate = calendar.date(byAdding: .day, value: index, to: day),
                  plan.days.contains(calendar.component(.weekday, from: candidate)),
                  let final = clock(on: candidate, minute: plan.finish, calendar: calendar),
                  final > date else { continue }
            dates.append(final)
            if dates.count == count { break }
        }
        return dates
    }

    static func nextOneTime(_ plan: Plan, now: Date, calendar: Calendar) throws -> Date {
        // Select the next complete window, including overnight windows.
        for index in 0...3 {
            guard let day = calendar.date(byAdding: .day, value: index, to: now),
                  let final = clock(on: day, minute: plan.finish, calendar: calendar) else { continue }
            if final.addingTimeInterval(Double(-plan.duration * 60)) > now { return final }
        }
        throw WakeError.message("Не удалось определить дату подъёма.")
    }

    static func signals(_ plan: Plan, defaults: Preferences, now: Date,
                        completed: Set<Occurrence>, calendar: Calendar) -> [Signal] {
        guard plan.enabled else { return [] }
        let options = plan.options ?? defaults
        let leads = plan.offsets(options).map { $0 - plan.duration }
        func signal(_ offset: Int, final: Date?) -> Signal {
            let rawMinute = plan.finish + offset
            let dayDelta = Int(floor(Double(rawMinute) / 1440))
            return Signal(planID: plan.id, name: plan.name, offset: offset,
                          minute: (rawMinute + 1440) % 1440,
                          days: final == nil ? shiftedDays(plan.days, by: dayDelta) : [],
                          fire: final?.addingTimeInterval(Double(offset * 60)),
                          occurrence: final.map { Occurrence(planID: plan.id, final: $0) }, options: options)
        }
        var result: [Signal] = []
        if !plan.days.isEmpty { result = leads.map { signal($0, final: nil) } }
        // Include this morning while its reserves can still ring, plus the following mornings.
        let start = now.addingTimeInterval(Double(-options.reserves * options.reserveGap * 60) - 1)
        let candidates = finals(plan, after: max(start, plan.activeSince ?? .distantPast), count: 4, calendar: calendar)
        for final in candidates.filter({ !completed.contains(Occurrence(planID: plan.id, final: $0)) }).prefix(3) {
            var offsets = plan.days.isEmpty ? leads : []
            for index in 0..<options.reserves { offsets.append((index + 1) * options.reserveGap) }
            result += offsets.map { signal($0, final: final) }.filter { ($0.fire ?? .distantPast) > now }
        }
        return result
    }

    static func recentFinal(_ plan: Plan, now: Date, calendar: Calendar) -> Date? {
        if plan.days.isEmpty { return plan.oneTimeFinal }
        let start = calendar.date(byAdding: .day, value: -8, to: now)!
        return finals(plan, after: max(start, plan.activeSince ?? .distantPast), count: 9, calendar: calendar).last { $0 <= now }
    }
}

