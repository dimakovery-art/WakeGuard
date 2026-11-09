import ActivityKit
import AlarmKit
import AppIntents
import SwiftUI

@MainActor
enum SystemAlarms {
    static let manager = AlarmManager.shared

    static func authorize() async throws {
        var status = manager.authorizationState
        if status == .notDetermined { status = try await manager.requestAuthorization() }
        guard status == .authorized else {
            throw WakeError.message("Разрешите будильники WakeGuard в настройках iPhone.")
        }
    }

    static func install(_ signal: Signal) async throws {
        let schedule: Alarm.Schedule
        if let date = signal.fire {
            schedule = .fixed(date)
        } else {
            let weekdays: [Locale.Weekday] = [.sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday]
            let time = Alarm.Schedule.Relative.Time(hour: signal.minute / 60, minute: signal.minute % 60)
            schedule = .relative(.init(time: time, repeats: .weekly(signal.days.sorted().map { weekdays[$0 - 1] })))
        }
        let math = signal.challengeButton
        let button = math
            ? AlarmButton(text: "Решить пример", textColor: .white, systemImageName: "function")
            : AlarmButton(text: "Ещё \(signal.options.snooze) мин", textColor: .white, systemImageName: "repeat")
        let title: LocalizedStringResource = "\(signal.name) · \(signal.phrase)"
        let alert: AlarmPresentation.Alert
        if #available(iOS 26.1, *) {
            alert = .init(title: title, secondaryButton: button, secondaryButtonBehavior: math ? .custom : .countdown)
        } else {
            let stop = AlarmButton(text: "Стоп", textColor: .white, systemImageName: "stop.fill")
            alert = .init(title: title, stopButton: stop, secondaryButton: button,
                          secondaryButtonBehavior: math ? .custom : .countdown)
        }
        let presentation = AlarmPresentation(alert: alert,
            countdown: math ? nil : .init(title: "Повтор · \(signal.name)", pauseButton: nil))
        let attributes = AlarmAttributes(presentation: presentation, metadata: WakeMetadata(planName: signal.name),
                                         tintColor: Color(red: 0.72, green: 0.32, blue: 0.07))
        let config = AlarmManager.AlarmConfiguration(
            countdownDuration: math ? nil : .init(preAlert: nil, postAlert: Double(signal.options.snooze * 60)),
            schedule: schedule, attributes: attributes, stopIntent: nil,
            secondaryIntent: math ? OpenChallengeIntent(id: signal.id) : nil,
            sound: signal.soundFile.map { AlertConfiguration.AlertSound.named($0) } ?? .default)
        _ = try await manager.schedule(id: signal.id, configuration: config)
    }
}

