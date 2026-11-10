import ActivityKit
import Foundation
import UserNotifications

/// Holds all app data and the tracking / blocking logic.
/// Shortcuts automations call into it through the intents in Intents.swift.
@MainActor
final class Engine: ObservableObject {
    static let shared = Engine()

    @Published var state: AppState {
        didSet {
            save()
            let scheduleChanged = oldValue.blocks != state.blocks
                || oldValue.scheduleOn != state.scheduleOn
                || oldValue.modes != state.modes
            if scheduleChanged { rescheduleReminders() }
            if scheduleChanged || oldValue.manualModeID != state.manualModeID || oldValue.liveOn != state.liveOn {
                Task { await refreshLive() }
            }
        }
    }

    /// Longest stretch counted for one open, in case iOS never sends "closed".
    let maxSession: TimeInterval = 90 * 60

    private static let fileURL: URL = {
        let dir = URL.applicationSupportDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(path: "focus-guard.json")
    }()

    private init() {
        if let data = try? Data(contentsOf: Self.fileURL),
           let saved = try? JSONDecoder().decode(AppState.self, from: data) {
            state = saved
        } else {
            state = AppState()
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(state) {
            try? data.write(to: Self.fileURL, options: .atomic)
        }
    }

    // MARK: Modes

    struct ActiveMode {
        let mode: FocusMode
        let detail: String
        let manual: Bool
    }

    func activeMode(at now: Date = .now) -> ActiveMode? {
        if let id = state.manualModeID, let mode = state.modes.first(where: { $0.id == id }) {
            return ActiveMode(mode: mode, detail: "On until you turn it off", manual: true)
        }
        guard state.scheduleOn,
              let block = state.blocks.first(where: { $0.contains(now) }),
              let mode = state.modes.first(where: { $0.id == block.modeID }) else { return nil }
        return ActiveMode(mode: mode, detail: "Scheduled until \(Clock.label(block.end))", manual: false)
    }

    // MARK: Usage

    func seconds(_ app: TrackedApp, now: Date = .now) -> Double {
        var total = state.today.seconds[app.key] ?? 0
        if let since = state.today.openSince[app.key] {
            total += min(max(now.timeIntervalSince(since), 0), maxSession)
        }
        return total
    }

    func isOpen(_ app: TrackedApp) -> Bool { state.today.openSince[app.key] != nil }

    func blockedCount(_ app: TrackedApp) -> Int { state.today.blocked[app.key] ?? 0 }

    /// Called by the "App Opened" Shortcuts action. Returns true when the app is blocked.
    func appOpened(_ raw: String) async -> Bool {
        let now = Date.now
        rollDay(now)
        let app = findOrAdd(raw)
        // Only one app is on screen at a time.
        closeAll(except: app.key, at: now)
        if let active = activeMode(at: now), active.mode.blocks.contains(app.category) {
            close(app.key, at: now)
            state.today.blocked[app.key, default: 0] += 1
            warn(app: app.name, mode: active.mode.name)
            await refreshLive(note: "\(app.name) blocked in \(active.mode.name)")
            return true
        }
        if state.today.openSince[app.key] == nil {
            state.today.openSince[app.key] = now
        }
        await refreshLive()
        return false
    }

    /// Called by the "App Closed" Shortcuts action.
    func appClosed(_ raw: String) async {
        let now = Date.now
        rollDay(now)
        if let app = find(raw) { close(app.key, at: now) }
        await refreshLive()
    }

    /// Focus Guard itself is on screen, so no tracked app is.
    func appBecameActive() async {
        let now = Date.now
        rollDay(now)
        closeAll(except: nil, at: now)
        await refreshLive()
    }

    func addApp(name: String, category: AppCategory) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, find(trimmed) == nil else { return }
        state.apps.append(TrackedApp(name: trimmed, category: category))
    }

    func find(_ raw: String) -> TrackedApp? {
        let n = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return state.apps.first { $0.name.lowercased() == n }
    }

    private func findOrAdd(_ raw: String) -> TrackedApp {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmed.isEmpty ? "Unknown app" : trimmed
        if let app = find(name) { return app }
        let app = TrackedApp(name: name, category: .guess(name))
        state.apps.append(app)
        return app
    }

    private func close(_ key: String, at now: Date) {
        guard let since = state.today.openSince.removeValue(forKey: key) else { return }
        state.today.seconds[key, default: 0] += min(max(now.timeIntervalSince(since), 0), maxSession)
    }

    private func closeAll(except keep: String?, at now: Date) {
        for key in Array(state.today.openSince.keys) where key != keep {
            close(key, at: now)
        }
    }

    private func rollDay(_ now: Date) {
        let key = Clock.dayKey(now)
        guard state.today.day != key else { return }
        let midnight = Calendar.current.startOfDay(for: now)
        var fresh = DayUsage(day: key)
        // Apps still open across midnight count from midnight.
        for (app, since) in state.today.openSince where now.timeIntervalSince(since) < maxSession {
            fresh.openSince[app] = max(since, midnight)
        }
        state.today = fresh
    }

    // MARK: Notifications

    func requestNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func warn(app: String, mode: String) {
        let content = UNMutableNotificationContent()
        content.title = "Warning: this is not allowed"
        content.body = "\(app) is blocked in \(mode) mode."
        content.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    /// A heads-up notification at the start of every schedule block.
    private func rescheduleReminders() {
        let blocks = state.scheduleOn ? state.blocks : []
        let modes = state.modes
        Task {
            let center = UNUserNotificationCenter.current()
            let old = await center.pendingNotificationRequests()
                .map(\.identifier)
                .filter { $0.hasPrefix("block-") }
            center.removePendingNotificationRequests(withIdentifiers: old)
            for block in blocks {
                guard let mode = modes.first(where: { $0.id == block.modeID }) else { continue }
                for day in block.days {
                    let content = UNMutableNotificationContent()
                    content.title = "\(mode.name) mode is on"
                    content.body = "Until \(Clock.label(block.end)). \(mode.summary)."
                    var when = DateComponents()
                    when.weekday = day
                    when.hour = block.start / 60
                    when.minute = block.start % 60
                    let request = UNNotificationRequest(
                        identifier: "block-\(block.id.uuidString)-\(day)",
                        content: content,
                        trigger: UNCalendarNotificationTrigger(dateMatching: when, repeats: true))
                    try? await center.add(request)
                }
            }
        }
    }

    // MARK: Top bar (Live Activity)

    func refreshLive(note: String? = nil) async {
        let existing = Activity<FocusAttributes>.activities
        guard state.liveOn, ActivityAuthorizationInfo().areActivitiesEnabled else {
            for activity in existing { await activity.end(nil, dismissalPolicy: .immediate) }
            return
        }
        let content = ActivityContent(state: liveState(note: note), staleDate: nil)
        let fresh = state.liveStarted.map { Date.now.timeIntervalSince($0) < 7 * 3600 } ?? false
        if fresh, let activity = existing.first {
            await activity.update(content)
            return
        }
        // iOS ends a Live Activity after 8 hours, so swap in a new one before that.
        for activity in existing { await activity.end(nil, dismissalPolicy: .immediate) }
        do {
            _ = try Activity.request(attributes: FocusAttributes(), content: content, pushType: nil)
            state.liveStarted = .now
        } catch {
            print("Live Activity failed: \(error)")
        }
    }

    private func liveState(note: String?) -> FocusAttributes.ContentState {
        let now = Date.now
        let ranked = state.apps
            .map { (app: $0, seconds: seconds($0, now: now)) }
            .sorted { $0.seconds > $1.seconds }
        let current = state.apps.first { isOpen($0) }
        let main = current.map { (app: $0, seconds: seconds($0, now: now)) } ?? ranked.first
        let rows = ranked
            .filter { $0.seconds >= 60 }
            .prefix(3)
            .map { FocusAttributes.Row(name: $0.app.name, seconds: $0.seconds) }
        return FocusAttributes.ContentState(
            appName: main?.app.name ?? "",
            seconds: main?.seconds ?? 0,
            liveSince: current.map { now.addingTimeInterval(-seconds($0, now: now)) },
            modeName: activeMode(at: now)?.mode.name,
            top: Array(rows),
            note: note)
    }
}
