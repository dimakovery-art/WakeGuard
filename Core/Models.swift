import Foundation

enum WakeMode: String, Codable, CaseIterable {
    case gentle = "Мягкий", standard = "Стандартный", insistent = "Настойчивый"
}

enum Difficulty: String, Codable, CaseIterable {
    case easy = "Лёгкая", medium = "Средняя", hard = "Сложная"
}

enum Melody: String, Codable, CaseIterable {
    case adaptive = "По режиму", chime = "Колокольчики", pulse = "Пульс", system = "Системный"
    case star = "Маленькая звезда", moon = "Au clair de la lune", bridge = "Лондонский мост"
    case yankee = "Янки Дудл", farm = "Ферма Макдональда", buns = "Hot Cross Buns"
    case saints = "Марш святых", rain = "Rain, Rain", mountain = "Coming Round the Mountain"
    case brother = "Братец Жак"

    static let tunes: [Melody] = [.star, .moon, .bridge, .yankee, .farm, .buns, .saints, .rain, .mountain, .brother]
    func resolved(for mode: WakeMode) -> Melody {
        switch self {
        case .adaptive: return mode == .insistent ? .yankee : .brother
        case .chime: return .star
        case .pulse: return .saints
        default: return self
        }
    }
}

struct Preferences: Codable, Equatable {
    var mode: WakeMode = .standard
    var math = true
    var count = 2
    var difficulty: Difficulty = .medium
    var snooze = 7
    var voice = true
    var melody: Melody = .adaptive
    // nil selects the mode's reserve count.
    var customReserves: Int?
    var reserveGap = 2
    var reserves: Int { max(math ? 1 : 0, customReserves ?? (mode == .gentle ? 0 : mode == .standard ? 2 : 3)) }
}

struct Plan: Identifiable, Codable, Equatable {
    var id = UUID()
    var name = "Подъём"
    var start = 510
    var finish = 540
    // Calendar weekday numbers, Sunday == 1. Days refer to the final alarm.
    var days: Set<Int> = []
    var enabled = true
    var options: Preferences?
    var manual: [Int]?
    var oneTimeFinal: Date?
    var activeSince: Date?
    var duration: Int { (finish - start + 1440) % 1440 }

    func offsets(_ preferences: Preferences) -> [Int] {
        manual ?? Schedule.offsets(duration: duration, mode: preferences.mode)
    }
}

struct Occurrence: Codable, Equatable, Hashable {
    var planID: UUID
    var final: Date
}

struct Signal: Identifiable, Codable, Equatable {
    var id = UUID()
    var audioRevision: Int? = 2
    var planID: UUID
    var name: String
    // Signed minute displacement from the final alarm.
    var offset: Int
    var minute: Int
    var days: Set<Int>
    var fire: Date?
    var occurrence: Occurrence?
    var options: Preferences

    func sameRequest(as other: Signal) -> Bool {
        var copy = other
        copy.id = id
        return copy == self
    }

    var challengeButton: Bool { offset >= 0 && options.math }
    var phrase: String {
        switch offset {
        case -10: return "До подъёма осталось десять минут"
        case -5: return "Осталось пять минут. Пора просыпаться!"
        case -2: return "Осталось две минуты! Срочно вставай!"
        case 0: return "Время подъёма! Вставай прямо сейчас!"
        case 1...: return "Резервный сигнал"
        default: return "Пора просыпаться"
        }
    }
    var soundFile: String? {
        let tune = options.melody.resolved(for: options.mode)
        guard let index = Melody.tunes.firstIndex(of: tune) else { return nil }
        let cue = options.voice ? String(min(0, offset)) : "music"
        return "wake2-\(index)-\(cue).wav"
    }
}

enum WakeError: LocalizedError {
    case message(String)
    var errorDescription: String? { switch self { case .message(let text): return text } }
}

func clockText(_ minute: Int) -> String {
    let m = (minute % 1440 + 1440) % 1440
    return String(format: "%02d:%02d", m / 60, m % 60)
}
