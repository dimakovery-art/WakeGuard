import ActivityKit
import AlarmKit
import SwiftUI
import WidgetKit

@main
struct WakeActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmAttributes<WakeMetadata>.self) { context in
            HStack(spacing: 14) {
                Image(systemName: "alarm.fill").foregroundStyle(.orange)
                VStack(alignment: .leading) {
                    Text(context.attributes.metadata?.planName ?? "WakeGuard").font(.headline)
                    Text("Следующий сигнал").font(.caption)
                }
                Spacer()
                Reading(mode: context.state.mode).font(.title2.bold())
            }
            .padding()
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Image(systemName: "alarm.fill").foregroundStyle(.orange) }
                DynamicIslandExpandedRegion(.trailing) { Reading(mode: context.state.mode) }
                DynamicIslandExpandedRegion(.bottom) { Text(context.attributes.metadata?.planName ?? "WakeGuard") }
            } compactLeading: {
                Image(systemName: "alarm.fill").foregroundStyle(.orange)
            } compactTrailing: {
                Reading(mode: context.state.mode).frame(maxWidth: 54)
            } minimal: {
                Image(systemName: "alarm.fill").foregroundStyle(.orange)
            }
        }
    }
}

private struct Reading: View {
    var mode: AlarmPresentationState.Mode
    var body: some View {
        switch mode {
        case .countdown(let state):
            Text(timerInterval: min(Date.now, state.fireDate)...state.fireDate, countsDown: true)
                .monospacedDigit().multilineTextAlignment(.trailing)
        case .paused: Text("Пауза")
        case .alert: Text("Подъём")
        @unknown default: Text("WakeGuard")
        }
    }
}

