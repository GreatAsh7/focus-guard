import ActivityKit
import SwiftUI
import WidgetKit

@main
struct FocusWidgets: WidgetBundle {
    var body: some Widget {
        FocusLiveActivity()
    }
}

struct FocusLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FocusAttributes.self) { context in
            LockScreenView(state: context.state)
                .padding(16)
                .activityBackgroundTint(Color(red: 0.07, green: 0.12, blue: 0.36))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let s = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(s.modeName ?? "No mode", systemImage: "scope")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    UsageTime(state: s).font(.headline.monospacedDigit())
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(s.appName.isEmpty ? "Nothing tracked yet today" : s.appName)
                            .font(.headline)
                        if let note = s.note {
                            Text(note).font(.caption).foregroundStyle(.orange)
                        }
                        TopRows(rows: s.top)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } compactLeading: {
                Text(Fmt.short(s.appName.isEmpty ? "Focus" : s.appName))
                    .font(.caption2.bold())
            } compactTrailing: {
                UsageTime(state: s)
                    .font(.caption2.monospacedDigit())
                    .frame(maxWidth: 52)
            } minimal: {
                Image(systemName: s.liveSince == nil ? "scope" : "timer")
            }
        }
    }
}

/// Ticks live while the app is open; otherwise shows today's total in 5-minute steps.
struct UsageTime: View {
    let state: FocusAttributes.ContentState

    var body: some View {
        if let since = state.liveSince {
            Text(timerInterval: since...Date.distantFuture, countsDown: false)
                .multilineTextAlignment(.trailing)
        } else {
            Text(Fmt.stepped(state.seconds))
        }
    }
}

struct TopRows: View {
    let rows: [FocusAttributes.Row]

    var body: some View {
        ForEach(rows, id: \.self) { row in
            HStack {
                Text(row.name)
                Spacer()
                Text(Fmt.stepped(row.seconds)).monospacedDigit()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

struct LockScreenView: View {
    let state: FocusAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Label(state.modeName ?? "No mode", systemImage: "scope")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                    Text(state.appName.isEmpty ? "Nothing tracked yet" : state.appName)
                        .font(.headline)
                        .foregroundStyle(.white)
                }
                Spacer()
                UsageTime(state: state)
                    .font(.title2.bold().monospacedDigit())
                    .foregroundStyle(.white)
            }
            if let note = state.note {
                Text(note).font(.caption).foregroundStyle(.orange)
            }
            TopRows(rows: state.top)
        }
    }
}
