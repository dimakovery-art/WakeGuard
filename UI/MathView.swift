import SwiftUI

struct MathView: View {
    @Environment(WakeStore.self) private var store
    @State private var cancelPrompt = false
    @State private var submitting = false
    @State private var errorMessage = ""
    @FocusState private var focused: Bool
    let key: Occurrence

    var body: some View {
        NavigationStack {
            if let challenge = store.state.challenges.first(where: { $0.id == key }) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        Label(store.state.plans.first { $0.id == key.planID }?.name ?? "WakeGuard", systemImage: "sunrise.fill")
                            .font(.headline).foregroundStyle(Color.accentColor)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Задание \(challenge.solved + 1) из \(challenge.total)").font(.title2.bold())
                            ProgressView(value: Double(challenge.solved), total: Double(challenge.total))
                        }
                        Text("\(challenge.problem.text) = ?")
                            .font(.system(size: 52, weight: .semibold, design: .rounded))
                            .minimumScaleFactor(0.55).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 10)
                        TextField("Ваш ответ", text: Binding(get: { challenge.input }, set: { store.type($0, for: key) }))
                            .font(.largeTitle.monospacedDigit()).keyboardType(.numberPad).focused($focused)
                            .padding().background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
                        if challenge.incorrect {
                            Label("Попробуйте ещё раз", systemImage: "arrow.counterclockwise").foregroundStyle(.red)
                        }
                        Button {
                            submitting = true
                            Task {
                                defer { submitting = false }
                                do { try await store.answer(key) } catch { errorMessage = error.localizedDescription }
                            }
                        } label: {
                            Text("Проверить ответ").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 8)
                        }.buttonStyle(.borderedProminent).disabled(challenge.input.isEmpty || submitting)
                        Button("Завершить этот подъём без примеров") { cancelPrompt = true }
                            .font(.subheadline).frame(maxWidth: .infinity)
                    }.padding(24)
                }
                .navigationTitle("Подтверждение").navigationBarTitleDisplayMode(.inline)
                .toolbar { Button("Позже") { store.presented = nil } }
                .sensoryFeedback(.error, trigger: challenge.incorrect) { _, new in new }
                .sensoryFeedback(.success, trigger: challenge.solved)
                .task { focused = true }
                .confirmationDialog("Отключить резервы этого подъёма?", isPresented: $cancelPrompt, titleVisibility: .visible) {
                    Button("Завершить подъём", role: .destructive) {
                        Task { do { try await store.finish(key) } catch { errorMessage = error.localizedDescription } }
                    }
                }
                .alert("Не удалось сохранить", isPresented: Binding(get: { !errorMessage.isEmpty }, set: { if !$0 { errorMessage = "" } })) {
                    Button("Понятно") { errorMessage = "" }
                } message: { Text(errorMessage) }
            }
        }.interactiveDismissDisabled()
    }
}

