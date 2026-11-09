import AppIntents
import Foundation

struct OpenChallengeIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Решить пример"
    static var supportedModes: IntentModes { .foreground }
    static var isDiscoverable: Bool = false
    @Parameter(title: "Идентификатор сигнала") var alarmID: String

    init() { alarmID = "" }
    init(id: UUID) { alarmID = id.uuidString }

    @MainActor func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: alarmID) { try WakeStore.shared.beginChallenge(alarmID: id) }
        return .result()
    }
}

