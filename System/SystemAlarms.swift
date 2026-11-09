import ActivityKit
import AVFoundation
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
        let button: AlarmButton? = math
            ? AlarmButton(text: "Решить пример", textColor: .white, systemImageName: "function")
            : nil
        let title: LocalizedStringResource = "\(signal.name) · \(signal.phrase)"
        let alert: AlarmPresentation.Alert
        if #available(iOS 26.1, *) {
            alert = .init(title: title, secondaryButton: button, secondaryButtonBehavior: math ? .custom : nil)
        } else {
            let stop = AlarmButton(text: "Стоп", textColor: .white, systemImageName: "stop.fill")
            alert = .init(title: title, stopButton: stop, secondaryButton: button,
                          secondaryButtonBehavior: math ? .custom : nil)
        }
        let presentation = AlarmPresentation(alert: alert)
        let attributes = AlarmAttributes(presentation: presentation, metadata: WakeMetadata(planName: signal.name),
                                         tintColor: Color(red: 0.72, green: 0.32, blue: 0.07))
        let audio = try await WakeAudio.prepare(signal)
        let config = AlarmManager.AlarmConfiguration(
            countdownDuration: nil,
            schedule: schedule, attributes: attributes, stopIntent: nil,
            secondaryIntent: math ? OpenChallengeIntent(id: signal.id) : nil,
            sound: audio.map { AlertConfiguration.AlertSound.named($0.lastPathComponent) } ?? .default)
        _ = try await manager.schedule(id: signal.id, configuration: config)
    }
}


// Instrumental arrangements of traditional melodies listed in the 8notes folk catalogue.
// Degrees 1...8 are the major scale. Durations are in beats.
enum WakeAudio {
    private static let themes = [
        "1 1 5 5 6 6 5:2 4 4 3 3 2 2 1:2",
        "1 1 1 2 3:2 2:2 1 3 2 2 1:4",
        "5 6 5 4 3 4 5:2 2 3 4:2 3 4 5:2",
        "1 1 2 3 1 3 2:2 1 1 2 3 1:2 7:2",
        "1 1 1 5 6 6 5:2 3 3 2 2 1:4",
        "3:2 2:2 1:4 3:2 2:2 1:4 1 1 1 1 2 2 2 2 3:2 2:2 1:4",
        "1 3 4 5:3 1 3 4 5:3 1 3 4 5:2 3:2 1:2 3:2 2:3",
        "5 3 5 5 3:2 5 5 3 6 5 5 3:2",
        "5 6 1 1 1 1 3 5 5 3 1:3 5 6 1 1 1 1 3 5 5:3",
        "1 2 3 1 1 2 3 1 3 4 5:2 3 4 5:2"
    ]
    private struct Speech {
        var samples: [Float] = []
        var rate = 22050.0
    }

    @MainActor
    static func prepare(_ signal: Signal) async throws -> URL? {
        guard let name = signal.soundFile,
              let index = Melody.tunes.firstIndex(of: signal.options.melody.resolved(for: signal.options.mode))
        else { return nil }
        let directory = try FileManager.default.url(for: .libraryDirectory, in: .userDomainMask,
                                                    appropriateFor: nil, create: true).appendingPathComponent("Sounds")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: url.path) { return url }
        var speech = Speech()
        if signal.options.voice {
            let minutes = -min(0, signal.offset)
            let unit: String
            switch (minutes % 100, minutes % 10) {
            case (11...14, _): unit = "минут"
            case (_, 1): unit = "минута"
            case (_, 2...4): unit = "минуты"
            default: unit = "минут"
            }
            let phrase = minutes == 0 ? "Время подъёма!" : "До подъёма \(minutes) \(unit)."
            speech = try await speak(phrase)
        }
        let recorded = speech
        let data = await Task.detached(priority: .userInitiated) {
            render(index: index, speech: recorded)
        }.value
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        return url
    }

    private static func speak(_ text: String) async throws -> Speech {
        let speaker = AVSpeechSynthesizer()
        defer { withExtendedLifetime(speaker) {} }
        let utterance = AVSpeechUtterance(string: text)
        let voices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("ru") }
        guard let voice = voices.max(by: { $0.quality.rawValue < $1.quality.rawValue }) else {
            throw WakeError.message("Добавьте русский голос в настройках речи iPhone или выключите голосовые предупреждения.")
        }
        utterance.voice = voice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.93
        return try await withCheckedThrowingContinuation { continuation in
            var result = Speech()
            var finished = false
            speaker.write(utterance) { buffer in
                guard !finished, let pcm = buffer as? AVAudioPCMBuffer else { return }
                if pcm.frameLength == 0 {
                    finished = true
                    if result.samples.isEmpty { continuation.resume(throwing: WakeError.message("Не удалось создать голосовой сигнал.")) }
                    else { continuation.resume(returning: result) }
                    return
                }
                result.rate = pcm.format.sampleRate
                let length = Int(pcm.frameLength)
                if let channel = pcm.floatChannelData?[0] {
                    result.samples.append(contentsOf: UnsafeBufferPointer(start: channel, count: length))
                } else if let channel = pcm.int16ChannelData?[0] {
                    result.samples += UnsafeBufferPointer(start: channel, count: length).map { Float($0) / 32768 }
                }
            }
        }
    }

    private static func render(index: Int, speech: Speech) -> Data {
        let scale = [0, 2, 4, 5, 7, 9, 11, 12]
        let notes = themes[index].split(separator: " ").map { token -> (Double, Double) in
            let parts = token.split(separator: ":")
            let degree = Int(parts[0])!
            let root = [330.0, 349, 311, 294, 330, 392, 311, 370, 294, 349][index]
            return (root * pow(2, Double(scale[degree - 1]) / 12), parts.count == 2 ? Double(parts[1])! : 1)
        }
        let rate = 22050
        let beats = notes.reduce(0.0) { $0 + $1.1 }
        let beat = 10 / beats
        let lead = 10 * rate
        let spokenFrames = Int(Double(speech.samples.count) * Double(rate) / speech.rate)
        let frames = lead + spokenFrames
        var pcm = Data(capacity: frames * 2)
        var note = 0, start = 0
        for frame in 0..<frames {
            let position = frame % lead
            if position == 0 { note = 0; start = 0 }
            let duration = max(1, Int(notes[note].1 * beat * Double(rate)))
            if position - start >= duration && note + 1 < notes.count { start += duration; note += 1 }
            let age = Double(position - start) / Double(rate)
            let phase = 2 * Double.pi * notes[note].0 * age
            let tail = notes[note].1 * beat - age
            let envelope = max(0, min(1, age / 0.012, tail / 0.035)) * exp(-age * 1.8)
            let timbre = sin(phase) + 0.22 * sin(phase * 2) + 0.1 * sin(phase * 3)
            let duck = speech.samples.isEmpty ? 1 : 1 - 0.82 * max(0, min(1, Double(frame - lead + 4400) / 4400))
            var value = 0.43 * timbre * envelope * duck
            if frame >= lead {
                let i = Int(Double(frame - lead) * speech.rate / Double(rate))
                value += 0.9 * Double(speech.samples[i])
            }
            let edge = min(1, Double(frame) / 220, Double(frames - frame) / 220)
            var sample = Int16(max(-1, min(1, value * edge)) * 32767).littleEndian
            withUnsafeBytes(of: &sample) { pcm.append(contentsOf: $0) }
        }
        var wav = Data("RIFF".utf8)
        func number<T: FixedWidthInteger>(_ value: T) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { wav.append(contentsOf: $0) }
        }
        number(UInt32(36 + pcm.count))
        wav.append(Data("WAVEfmt ".utf8))
        number(UInt32(16)); number(UInt16(1)); number(UInt16(1))
        number(UInt32(rate)); number(UInt32(rate * 2)); number(UInt16(2)); number(UInt16(16))
        wav.append(Data("data".utf8)); number(UInt32(pcm.count)); wav.append(pcm)
        return wav
    }
}
