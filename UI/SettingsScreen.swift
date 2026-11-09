import AVFoundation
import AlarmKit
import SwiftUI

struct DaysView: View {
    @Binding var days: Set<Int>
    static let labels = ["Вс", "Пн", "Вт", "Ср", "Чт", "Пт", "Сб"]
    static let order = [2, 3, 4, 5, 6, 7, 1]
    static func summary(_ days: Set<Int>) -> String {
        switch days {
        case []: return "Один раз"
        case Set(2...6): return "Будни"
        case [1, 7]: return "Выходные"
        case Set(1...7): return "Каждый день"
        default: return order.filter(days.contains).map { labels[$0 - 1] }.joined(separator: ", ")
        }
    }
    var body: some View {
        Menu {
            Button("Один раз") { days = [] }
            Button("Каждый день") { days = Set(1...7) }
            Button("Будни") { days = Set(2...6) }
            Button("Выходные") { days = [1, 7] }
        } label: { LabeledContent("Повторять", value: Self.summary(days)) }
        HStack(spacing: 2) {
            ForEach(Self.order, id: \.self) { day in
                Button {
                    if days.contains(day) { days.remove(day) } else { days.insert(day) }
                } label: {
                    Text(Self.labels[day - 1]).font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 42)
                        .background(days.contains(day) ? Color.accentColor.opacity(0.18) : .clear, in: Capsule())
                }.buttonStyle(.plain).accessibilityAddTraits(days.contains(day) ? .isSelected : [])
            }
        }
    }
}

struct OptionsFields: View {
    @Binding var options: Preferences
    @State private var player: AVAudioPlayer?
    @State private var audioError = ""
    var body: some View {
        Section("Пробуждение") {
            Picker("Режим", selection: $options.mode) {
                ForEach(WakeMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
        }
        Section("Звук") {
            Picker("Мелодия", selection: Binding(get: { options.melody.resolved(for: options.mode) }, set: { options.melody = $0 })) {
                ForEach(Melody.tunes + [.system], id: \.self) { Text($0.rawValue).tag($0) }
            }
            Toggle("Произносить время поверх мелодии", isOn: $options.voice)
            Button("Послушать сигнал за 10 минут", systemImage: "speaker.wave.2") {
                let sample = Signal(planID: UUID(), name: "", offset: -10, minute: 0, days: [], options: options)
                Task {
                    do {
                        guard let url = try await WakeAudio.prepare(sample) else {
                            audioError = "Системный звук можно услышать при срабатывании будильника."
                            return
                        }
                        player?.stop()
                        player = try AVAudioPlayer(contentsOf: url)
                        player?.numberOfLoops = 1
                        player?.play()
                    } catch { audioError = error.localizedDescription }
                }
            }
            .alert("Прослушивание", isPresented: Binding(get: { !audioError.isEmpty }, set: { if !$0 { audioError = "" } })) {
                Button("Понятно") { audioError = "" }
            } message: { Text(audioError) }
        }.onDisappear { player?.stop() }
        Section("Подтверждение подъёма") {
            Toggle("Решить примеры", isOn: $options.math)
            if options.math {
                Stepper("Примеров: \(options.count)", value: $options.count, in: 1...3)
                Picker("Сложность", selection: $options.difficulty) {
                    ForEach(Difficulty.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
            }
        }
        Section {
            Picker("Резервных сигналов", selection: Binding(get: { options.customReserves.map { _ in options.reserves } }, set: { options.customReserves = $0 })) {
                Text("По режиму").tag(nil as Int?)
                ForEach((options.math ? 1 : 0)...5, id: \.self) { Text("\($0)").tag(Optional($0)) }
            }
            if options.reserves > 0 {
                Stepper("Интервал: \(options.reserveGap) мин", value: $options.reserveGap, in: 1...10)
            }
        } header: {
            Text("Резерв после подъёма")
        } footer: {
            Text("При включённых примерах будет хотя бы один резервный звонок. Решение примеров отменяет оставшиеся звонки этого подъёма. Резерв на три ближайших подъёма пополняется при открытии приложения. Основные сигналы повторяются по расписанию iOS.")
        }
    }
}

struct SettingsScreen: View {
    @Environment(WakeStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var options = Preferences()
    @State private var days: Set<Int> = []
    @State private var loaded = false
    var body: some View {
        Form {
            Section {
                LabeledContent("Будильники", value: accessText)
                if store.authorization == .notDetermined {
                    Button("Запросить доступ") {
                        Task {
                            do { try await SystemAlarms.authorize() } catch { store.message = error.localizedDescription }
                            await store.refresh()
                        }
                    }
                } else if store.authorization != .authorized {
                    Button("Открыть настройки iPhone") { openURL(URL(string: UIApplication.openSettingsURLString)!) }
                }
            } header: { Text("Разрешение iOS") }
            OptionsFields(options: $options)
            Section("Дни для новых планов") { DaysView(days: $days) }
        }
        .navigationTitle("Настройки").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button("Сохранить") {
                Task {
                    do { try await store.setDefaults(options, days: days); dismiss() }
                    catch { store.message = error.localizedDescription }
                }
            }.disabled(store.busy)
        }
        .onAppear {
            if !loaded { options = store.state.defaults; days = store.state.defaultDays; loaded = true }
        }
    }
    private var accessText: String {
        switch store.authorization {
        case .authorized: return "Разрешены"
        case .denied: return "Доступ закрыт"
        case .notDetermined: return "Требуется запрос"
        @unknown default: return "Неизвестно"
        }
    }
}
