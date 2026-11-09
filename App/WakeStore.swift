import AlarmKit
import Foundation
import Observation

@MainActor @Observable
final class WakeStore {
    static let shared = WakeStore()
    private let disk = Storage(url: URL.applicationSupportDirectory.appending(path: "WakeGuard/state-v1.json"))
    private(set) var state = SavedState()
    private(set) var authorization = SystemAlarms.manager.authorizationState
    private(set) var liveIDs: Set<UUID> = []
    private(set) var busy = false
    private(set) var syncIssue: String?
    private(set) var unreadable = false
    var message: String?
    var presented: Occurrence?
    private var dirty = false
    @ObservationIgnored private var waiters: [CheckedContinuation<Void, Never>] = []

    private init() {
        do {
            state = try disk.read()
            presented = state.challenges.first?.occurrence
        } catch {
            unreadable = true
            message = "Не удалось прочитать сохранённые планы. Исходный файл сохранён. \(error.localizedDescription)"
        }
    }

    private func change(_ edit: (inout SavedState) -> Void) throws {
        guard !unreadable else { throw WakeError.message("Хранилище недоступно.") }
        var next = state
        edit(&next)
        try disk.write(next)
        state = next
    }

    func save(_ value: Plan) async throws {
        var plan = value
        guard plan.duration > 0 else { throw WakeError.message("Укажите разные времена начала и подъёма.") }
        guard !plan.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw WakeError.message("Введите название плана.")
        }
        let old = state.plans.first { $0.id == plan.id }
        if plan.enabled {
            try await SystemAlarms.authorize()
            if old?.enabled != true || old?.days != plan.days || old?.start != plan.start || old?.finish != plan.finish {
                plan.activeSince = .now
            }
            if plan.days.isEmpty && (plan.oneTimeFinal == nil || old?.enabled != true ||
                old?.days != plan.days || old?.start != plan.start || old?.finish != plan.finish) {
                plan.oneTimeFinal = try Schedule.nextOneTime(plan, now: .now, calendar: .current)
            }
        }
        if !plan.days.isEmpty { plan.oneTimeFinal = nil }
        try change { data in
            if let i = data.plans.firstIndex(where: { $0.id == plan.id }) { data.plans[i] = plan }
            else { data.plans.append(plan) }
            if !plan.enabled { data.challenges.removeAll { $0.occurrence.planID == plan.id } }
        }
        if !plan.enabled && presented?.planID == plan.id { presented = nil }
        await refresh()
    }

    func delete(_ id: UUID) async throws {
        try change { data in
            data.plans.removeAll { $0.id == id }
            data.challenges.removeAll { $0.occurrence.planID == id }
        }
        if presented?.planID == id { presented = nil }
        await refresh()
    }

    func setDefaults(_ preferences: Preferences, days: Set<Int>) async throws {
        try change { $0.defaults = preferences; $0.defaultDays = days }
        await refresh()
    }

    func observe() async {
        for await alarms in SystemAlarms.manager.alarmUpdates {
            liveIDs = Set(alarms.map(\.id))
        }
    }

    func observeAccess() async {
        for await value in SystemAlarms.manager.authorizationUpdates {
            authorization = value
            await refresh()
        }
    }

    func refresh() async {
        authorization = SystemAlarms.manager.authorizationState
        guard !unreadable else { return }
        dirty = true
        if busy {
            await withCheckedContinuation { waiters.append($0) }
            return
        }
        busy = true
        defer {
            busy = false
            let pending = waiters
            waiters.removeAll()
            for waiter in pending { waiter.resume() }
        }
        repeat {
            dirty = false
            do { try await reconcile(); syncIssue = nil }
            catch { syncIssue = "Сверка с iOS не завершена. \(error.localizedDescription)" }
        } while dirty
    }

    private func reconcile() async throws {
        guard authorization == .authorized else {
            liveIDs = []
            if state.plans.contains(where: \.enabled) || !state.ledger.isEmpty {
                throw WakeError.message("Проверьте разрешение на будильники.")
            }
            return
        }
        let manager = SystemAlarms.manager
        let live = try manager.alarms
        liveIDs = Set(live.map(\.id))
        let now = Date.now
        let activeIDs = Set(live.filter { $0.state != .scheduled }.map(\.id))
        let desired = state.plans.flatMap {
            Schedule.signals($0, defaults: state.defaults, now: now, completed: state.completed, calendar: .current)
        }
        // Keep the original UUID across retries, even if the process died during schedule().
        var keep = desired.map { item in state.ledger.first { $0.sameRequest(as: item) } ?? item }
        let keepIDs = Set(keep.map(\.id))
        for old in state.ledger where !keepIDs.contains(old.id) {
            let unchanged = state.plans.contains {
                $0.id == old.planID && $0.enabled && $0.name == old.name &&
                    ($0.options ?? state.defaults) == old.options &&
                    ($0.days.isEmpty ? $0.oneTimeFinal == old.occurrence?.final : old.offset > 0)
            }
            let done = old.occurrence.map(state.completed.contains) ?? false
            // A fixed alarm can be ringing, snoozed, or opening its intent just after its scheduled time.
            if unchanged && !done, let fire = old.fire, fire <= now,
               activeIDs.contains(old.id) || now.timeIntervalSince(fire) < 7200 {
                keep.append(old)
                continue
            }
            if liveIDs.contains(old.id) { try manager.cancel(id: old.id); liveIDs.remove(old.id) }
        }
        if keep != state.ledger { try change { $0.ledger = keep } }

        // stop() finishes a live occurrence. Keep the recurring registration.
        for record in keep where record.fire == nil && activeIDs.contains(record.id) {
            guard let plan = state.plans.first(where: { $0.id == record.planID }) else { continue }
            var firingClock = plan
            firingClock.days = record.days
            firingClock.finish = record.minute
            let calendar = Calendar.current
            guard let firing = Schedule.recentFinal(firingClock, now: now, calendar: calendar),
                  let day = calendar.date(byAdding: .day, value: plan.finish + record.offset < 0 ? 1 : 0, to: firing),
                  let final = Schedule.clock(on: day, minute: plan.finish, calendar: calendar),
                  state.completed.contains(Occurrence(planID: plan.id, final: final)) else { continue }
            try manager.stop(id: record.id)
        }

        // A system limit or a bad request in one plan must not prevent trying other plans.
        var failure: Error?
        let prioritized = keep.sorted { a, b in
            if (a.offset > 0) != (b.offset > 0) { return a.offset <= 0 }
            return (a.fire ?? .distantPast) < (b.fire ?? .distantPast)
        }
        for record in prioritized where !liveIDs.contains(record.id) {
            if dirty { return }
            if let date = record.fire, date <= Date.now { continue }
            do {
                try await SystemAlarms.install(record)
                liveIDs.insert(record.id)
            } catch AlarmManager.AlarmError.maximumLimitReached {
                failure = WakeError.message("Достигнут лимит будильников iOS. Уменьшите число резервов или отключите лишний план.")
            } catch { failure = error }
        }
        if let failure { throw failure }

        // Keep short-lived intent routing records, but retire finished one-shot plans.
        let expired = state.plans.filter { plan in
            guard plan.enabled, plan.days.isEmpty, let final = plan.oneTimeFinal else { return false }
            let options = plan.options ?? state.defaults
            let end = final.addingTimeInterval(Double(options.reserves * options.reserveGap * 60))
            return end < now && !state.ledger.contains { $0.planID == plan.id && activeIDs.contains($0.id) }
                && !state.challenges.contains { $0.occurrence.planID == plan.id }
                && now.timeIntervalSince(end) > 7200
        }.map(\.id)
        let cutoff = now.addingTimeInterval(-2 * 86400)
        if !expired.isEmpty || state.completed.contains(where: { $0.final < cutoff }) {
            try change { data in
                for i in data.plans.indices where expired.contains(data.plans[i].id) { data.plans[i].enabled = false }
                data.completed = data.completed.filter { $0.final >= cutoff }
            }
        }
    }

    func beginChallenge(alarmID: UUID) throws {
        guard let signal = state.ledger.first(where: { $0.id == alarmID && $0.challengeButton }),
              let plan = state.plans.first(where: { $0.id == signal.planID && $0.enabled }) else { return }
        let final = signal.occurrence?.final ?? Schedule.recentFinal(plan, now: .now, calendar: .current)
        guard let final, final <= .now, Date.now.timeIntervalSince(final) < 7200 else { return }
        try open(plan, final: final)
    }

    func open(_ plan: Plan, final: Date) throws {
        let key = Occurrence(planID: plan.id, final: final)
        guard !state.completed.contains(key), plan.enabled else { return }
        let options = plan.options ?? state.defaults
        if !state.challenges.contains(where: { $0.id == key }) {
            let problem = Problem.draw(options.difficulty, excluding: state.lastProblem)
            try change {
                $0.challenges.append(Challenge(occurrence: key, level: options.difficulty,
                                              total: options.count, problem: problem))
                $0.lastProblem = problem
            }
        }
        presented = key
    }

    func type(_ value: String, for key: Occurrence) {
        do {
            try change { data in
                guard let i = data.challenges.firstIndex(where: { $0.id == key }) else { return }
                data.challenges[i].input = String(value.filter(\.isNumber).prefix(5))
                data.challenges[i].incorrect = false
            }
        } catch { message = error.localizedDescription }
    }

    func answer(_ key: Occurrence) async throws {
        guard var task = state.challenges.first(where: { $0.id == key }) else { return }
        _ = task.submit()
        if task.solved == task.total {
            try await finish(key)
        } else {
            try change { data in
                if let i = data.challenges.firstIndex(where: { $0.id == key }) { data.challenges[i] = task }
                data.lastProblem = task.problem
            }
        }
    }

    func finish(_ key: Occurrence) async throws {
        // Persist confirmation before cancelling. On interruption, reconciliation retries cleanup.
        try change { data in
            data.completed.insert(key)
            data.challenges.removeAll { $0.id == key }
            if let i = data.plans.firstIndex(where: { $0.id == key.planID && $0.days.isEmpty && $0.oneTimeFinal == key.final }) {
                data.plans[i].enabled = false
            }
        }
        presented = state.challenges.first?.id
        await refresh()
        message = syncIssue ?? "Подъём подтверждён. Резервные сигналы этого подъёма отключены."
    }
}

