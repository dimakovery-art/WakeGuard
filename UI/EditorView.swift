import SwiftUI

struct EditorView: View {
    @Environment(WakeStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State var plan: Plan
    @State private var deletePrompt = false
    @State private var saving = false
    private var existing: Bool { store.state.plans.contains { $0.id == plan.id } }
    private var options: Preferences { plan.options ?? store.state.defaults }
    private var offsets: [Int] { plan.offsets(options) }

    var body: some View {
        Form {
            Section("План") { TextField("Название", text: $plan.name) }
            Section {
                DatePicker("Начать будить", selection: time(\.start), displayedComponents: .hourAndMinute)
                DatePicker("Нужно встать", selection: time(\.finish), displayedComponents: .hourAndMinute)
            } footer: {
                if plan.start == plan.finish { Text("Времена должны различаться.") }
                else if plan.start > plan.finish { Text("Первый сигнал прозвучит накануне дня подъёма.") }
                else if plan.days.isEmpty, let final = try? Schedule.nextOneTime(plan, now: .now, calendar: .current) {
                    Text("Ближайшее полное окно: \(final.formatted(.dateTime.locale(Locale(identifier: "ru_RU")).weekday(.wide).day().month(.wide))).")
                }
            }
            Section("Дни подъёма") { DaysView(days: $plan.days) }
            Section("Расписание") {
                Toggle("Настроить вручную", isOn: Binding(get: { plan.manual != nil }, set: { on in
                    plan.manual = on ? Schedule.offsets(duration: plan.duration, mode: options.mode) : nil
                }))
                if plan.manual != nil && plan.duration > 0 {
                    Stepper("Сигналов: \(offsets.count)", value: Binding(get: { offsets.count }, set: {
                        plan.manual = Schedule.evenly(plan.duration, count: $0)
                    }), in: 2...min(16, plan.duration + 1))
                }
                ForEach(Array(offsets.indices), id: \.self) { index in row(index) }
            }
            if options.reserves > 0 {
                Section("После финального сигнала") {
                    ForEach(1...options.reserves, id: \.self) { i in
                        LabeledContent("Резерв \(i)", value: clockText(plan.finish + i * options.reserveGap))
                    }
                }
            }
            Section {
                Toggle("Свои настройки плана", isOn: Binding(get: { plan.options != nil }, set: {
                    plan.options = $0 ? store.state.defaults : nil
                }))
            } footer: { if plan.options == nil { Text("Используются общие настройки WakeGuard.") } }
            if plan.options != nil {
                OptionsFields(options: Binding(get: { options }, set: { plan.options = $0 }))
            }
            if existing {
                Section { Button("Удалить план", role: .destructive) { deletePrompt = true } }
            }
        }
        .navigationTitle(existing ? "Изменить план" : "Новый план")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button("Сохранить") {
                saving = true
                Task {
                    defer { saving = false }
                    do { try await store.save(plan); dismiss() } catch { store.message = error.localizedDescription }
                }
            }.disabled(plan.duration == 0 || saving || store.busy || plan.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .confirmationDialog("Удалить план и все его сигналы?", isPresented: $deletePrompt, titleVisibility: .visible) {
            Button("Удалить план", role: .destructive) {
                Task {
                    do { try await store.delete(plan.id); dismiss() } catch { store.message = error.localizedDescription }
                }
            }
        }
    }

    private func time(_ key: WritableKeyPath<Plan, Int>) -> Binding<Date> {
        Binding(get: {
            Schedule.clock(on: .now, minute: plan[keyPath: key], calendar: .current) ?? .now
        }, set: { date in
            let calendar = Calendar.current
            plan[keyPath: key] = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
            if plan.manual != nil { plan.manual = Schedule.evenly(plan.duration, count: offsets.count) }
        })
    }

    @ViewBuilder private func row(_ i: Int) -> some View {
        if offsets.indices.contains(i) {
            let offset = offsets[i]
            HStack {
                Image(systemName: i == offsets.count - 1 ? "sunrise.fill" : "bell")
                    .foregroundStyle(i == offsets.count - 1 ? Color.accentColor : .secondary)
                    .frame(width: 22)
                VStack(alignment: .leading) {
                    Text(clockText(plan.start + offset)).font(.headline.monospacedDigit())
                    Text(i == offsets.count - 1 ? "Финальный подъём" : i == 0 ? "Первый сигнал" : "За \(plan.duration - offset) мин")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if plan.manual != nil && i > 0 && i < offsets.count - 1 {
                    let low = offsets[i - 1] + 1, high = offsets[i + 1] - 1
                    Stepper("Время сигнала", value: Binding(get: { offset }, set: { newValue in
                        if var manual = plan.manual, manual.indices.contains(i) {
                            manual[i] = min(high, max(low, newValue))
                            plan.manual = manual
                        }
                    }), in: low...high).labelsHidden().frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
    }
}

