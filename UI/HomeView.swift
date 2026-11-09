import AlarmKit
import SwiftUI

extension Occurrence: Identifiable { var id: Self { self } }

struct HomeView: View {
    @Environment(WakeStore.self) private var store
    @State private var editor: Plan?
    @State private var settings = false
    var body: some View {
        @Bindable var store = store
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 60)) { timeline in
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        SunriseCard(next: next(at: timeline.date))
                        if let issue = store.syncIssue {
                            VStack(alignment: .leading, spacing: 8) {
                                Label(issue, systemImage: "exclamationmark.triangle").font(.subheadline)
                                Button("Повторить проверку") { Task { await store.refresh() } }
                            }.padding().background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
                        }
                        HStack {
                            Text("Мои планы").font(.title2.bold())
                            Spacer()
                            if store.busy { ProgressView().accessibilityLabel("Сверка с iOS") }
                        }
                        if store.state.plans.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Во сколько вас разбудить?").font(.headline)
                                Text("Выберите время первого сигнала и время подъёма.").foregroundStyle(.secondary)
                                Button("Создать план", systemImage: "plus", action: add).buttonStyle(.borderedProminent)
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(20).card()
                        }
                        ForEach(store.state.plans) { plan in
                            PlanCard(plan: plan, now: timeline.date, edit: { editor = plan })
                        }
                    }.padding(.horizontal, 20).padding(.vertical, 12)
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("WakeGuard")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Настройки", systemImage: "gearshape") { settings = true }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Создать план", systemImage: "plus", action: add)
                }
            }
            .navigationDestination(isPresented: $settings) { SettingsScreen() }
            .navigationDestination(isPresented: Binding(get: { editor != nil }, set: { if !$0 { editor = nil } })) {
                if let editor { EditorView(plan: editor).id(editor.id) }
            }
        }
        .fullScreenCover(item: $store.presented) { key in MathView(key: key) }
        .alert("WakeGuard", isPresented: Binding(get: { store.message != nil }, set: { if !$0 { store.message = nil } })) {
            Button("Понятно") { store.message = nil }
        } message: { Text(store.message ?? "") }
    }

    private func next(at now: Date) -> (Plan, Date)? {
        guard store.authorization == .authorized else { return nil }
        return store.state.plans.filter(\.enabled).compactMap { plan -> (Plan, Date)? in
            guard store.state.ledger.contains(where: { $0.planID == plan.id && $0.offset == 0 && store.liveIDs.contains($0.id) }),
                  let date = Schedule.finals(plan, after: now, count: 1, calendar: .current).first else { return nil }
            return (plan, date)
        }.min { $0.1 < $1.1 }
    }
    private func add() {
        var plan = Plan()
        plan.days = store.state.defaultDays
        editor = plan
    }
}

private struct SunriseCard: View {
    var next: (Plan, Date)?
    @Environment(\.colorScheme) var theme
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Следующий подъём", systemImage: "sunrise.fill").font(.headline)
            if let (plan, date) = next {
                Text(date, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute())
                    .font(.system(size: 64, weight: .medium, design: .rounded)).monospacedDigit()
                Text("\(plan.name) · \(date.formatted(.dateTime.locale(Locale(identifier: "ru_RU")).weekday(.wide).day().month(.wide)))")
            } else {
                Text("Пока не назначен").font(.largeTitle.weight(.medium)).padding(.vertical, 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(24)
        .foregroundStyle(theme == .dark ? Color(red: 1, green: 0.90, blue: 0.78) : Color(red: 0.24, green: 0.14, blue: 0.08))
        .background {
            LinearGradient(colors: theme == .dark ? [Color(red: 0.23, green: 0.16, blue: 0.19), Color(red: 0.38, green: 0.23, blue: 0.14)] :
                            [Color(red: 1, green: 0.94, blue: 0.85), Color(red: 1, green: 0.82, blue: 0.65)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "sun.horizon").font(.system(size: 118, weight: .thin))
                        .opacity(0.11).offset(x: 30, y: 24).accessibilityHidden(true)
                }.clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
    }
}

private struct PlanCard: View {
    @Environment(WakeStore.self) var store
    let plan: Plan
    var now: Date
    var edit: () -> Void
    @State private var pendingFinish: Occurrence?
    private var options: Preferences { plan.options ?? store.state.defaults }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button(action: edit) { Label(plan.name, systemImage: "alarm").font(.headline) }.buttonStyle(.plain)
                Spacer()
                Toggle("Активен", isOn: Binding(get: { plan.enabled }, set: { on in
                    var updated = plan
                    updated.enabled = on
                    Task { do { try await store.save(updated) } catch { store.message = error.localizedDescription } }
                })).labelsHidden().disabled(store.busy)
            }
            Button(action: edit) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("\(clockText(plan.start)) → \(clockText(plan.finish))")
                        .font(.system(.title, design: .rounded, weight: .semibold)).monospacedDigit()
                    Text("\(DaysView.summary(plan.days)) · Сигналов: \(plan.offsets(options).count)")
                        .font(.subheadline).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain)
            if plan.enabled && options.reserves > 0 && !plan.days.isEmpty {
                let last = store.state.ledger.filter { $0.planID == plan.id && $0.offset > 0 && store.liveIDs.contains($0.id) }
                    .compactMap(\.occurrence?.final).max()
                if let last {
                    Text("Резерв до \(last.formatted(.dateTime.locale(Locale(identifier: "ru_RU")).day().month(.wide))) включительно")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if plan.enabled, let final = Schedule.recentFinal(plan, now: now, calendar: .current),
               final <= now && now.timeIntervalSince(final) < 7200,
               !store.state.completed.contains(Occurrence(planID: plan.id, final: final)) {
                if options.math {
                    Button("Подтвердить подъём", systemImage: "function") {
                        do { try store.open(plan, final: final) } catch { store.message = error.localizedDescription }
                    }
                } else {
                    Button("Я встал · отключить резерв", systemImage: "checkmark") {
                        pendingFinish = Occurrence(planID: plan.id, final: final)
                    }
                }
            }
        }.padding(18).card().sensoryFeedback(.selection, trigger: plan.enabled)
        .confirmationDialog("Завершить этот подъём?", isPresented: Binding(get: { pendingFinish != nil },
            set: { if !$0 { pendingFinish = nil } }), presenting: pendingFinish) { key in
            Button("Отключить резерв", role: .destructive) {
                Task { do { try await store.finish(key) } catch { store.message = error.localizedDescription } }
            }
        }
    }
}

extension View {
    func card() -> some View {
        background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 21))
    }
}

