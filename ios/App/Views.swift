import SwiftUI

// MARK: Today

struct TodayView: View {
    @EnvironmentObject private var engine: Engine
    @State private var adding = false
    @State private var editing: TrackedApp?

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                List {
                    Section { ModeBanner() }

                    Section {
                        ForEach(sortedApps(context.date)) { app in
                            Button { editing = app } label: {
                                AppRow(app: app, now: context.date)
                            }
                            .buttonStyle(.plain)
                        }
                        .onDelete { offsets in
                            let ids = offsets.map { sortedApps(context.date)[$0].id }
                            engine.state.apps.removeAll { ids.contains($0.id) }
                        }
                    } header: {
                        Text("Today · \(Fmt.duration(total(context.date))) on tracked apps")
                    } footer: {
                        Text("Apps count once you add their automations in the Setup tab.")
                    }

                    Section {
                        Toggle("Show in the top bar", isOn: $engine.state.liveOn)
                    } footer: {
                        Text("Shows on the Lock Screen and in the Dynamic Island. It ticks live while a tracked app is open, otherwise it goes up in 5-minute steps.")
                    }
                }
            }
            .navigationTitle("Focus Guard")
            .toolbar {
                Button { adding = true } label: { Image(systemName: "plus") }
            }
            .sheet(isPresented: $adding) { AddAppSheet() }
            .sheet(item: $editing) { app in EditAppSheet(app: app) }
        }
    }

    private func sortedApps(_ now: Date) -> [TrackedApp] {
        engine.state.apps.sorted { engine.seconds($0, now: now) > engine.seconds($1, now: now) }
    }

    private func total(_ now: Date) -> Double {
        engine.state.apps.reduce(0) { $0 + engine.seconds($1, now: now) }
    }
}

struct ModeBanner: View {
    @EnvironmentObject private var engine: Engine

    var body: some View {
        if let active = engine.activeMode() {
            HStack(spacing: 12) {
                Image(systemName: active.mode.symbol)
                    .font(.title2)
                    .foregroundStyle(.tint)
                    .frame(width: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(active.mode.name) mode").font(.headline)
                    Text("\(active.detail) · \(active.mode.summary)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if active.manual {
                    Button("Turn off") { engine.state.manualModeID = nil }
                        .buttonStyle(.bordered)
                }
            }
        } else {
            HStack(spacing: 12) {
                Image(systemName: "scope")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .frame(width: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text("No mode on").font(.headline)
                    Text("Everything is allowed. Pick a mode in the Modes tab.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct AppRow: View {
    @EnvironmentObject private var engine: Engine
    let app: TrackedApp
    let now: Date

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: app.category.symbol)
                .foregroundStyle(.tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(app.name)
                let blocked = engine.blockedCount(app)
                Text(blocked > 0 ? "\(app.category.label) · blocked \(blocked)×" : app.category.label)
                    .font(.caption)
                    .foregroundStyle(blocked > 0 ? Color.orange : Color.secondary)
            }
            Spacer()
            if engine.isOpen(app) {
                Text("NOW")
                    .font(.caption2.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.green.opacity(0.2), in: Capsule())
                    .foregroundStyle(.green)
            }
            Text(Fmt.duration(engine.seconds(app, now: now)))
                .monospacedDigit()
        }
        .contentShape(Rectangle())
    }
}

struct AddAppSheet: View {
    @EnvironmentObject private var engine: Engine
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var category: AppCategory = .other
    @State private var pickedCategory = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("App name, e.g. Snapchat", text: $name)
                        .onChange(of: name) { _, newName in
                            if !pickedCategory { category = .guess(newName) }
                        }
                } footer: {
                    Text("Use the same name in the Shortcuts automation. Apps you set up in Shortcuts first are added here by themselves.")
                }
                Picker("Type", selection: Binding(
                    get: { category },
                    set: { category = $0; pickedCategory = true })) {
                    ForEach(AppCategory.allCases) { Label($0.label, systemImage: $0.symbol).tag($0) }
                }
            }
            .navigationTitle("Track an app")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        engine.addApp(name: name, category: category)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

struct EditAppSheet: View {
    @EnvironmentObject private var engine: Engine
    @Environment(\.dismiss) private var dismiss
    @State var app: TrackedApp

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $app.name)
                } footer: {
                    Text("If you rename it, change the name in its Shortcuts automations too.")
                }
                Picker("Type", selection: $app.category) {
                    ForEach(AppCategory.allCases) { Label($0.label, systemImage: $0.symbol).tag($0) }
                }
            }
            .navigationTitle(app.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let i = engine.state.apps.firstIndex(where: { $0.id == app.id }) {
                            engine.state.apps[i] = app
                        }
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: Modes

struct ModesView: View {
    @EnvironmentObject private var engine: Engine

    var body: some View {
        NavigationStack {
            List {
                Section { ModeBanner() }

                Section {
                    ForEach(engine.state.modes) { mode in
                        let on = engine.state.manualModeID == mode.id
                        Button {
                            engine.state.manualModeID = on ? nil : mode.id
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: mode.symbol)
                                    .foregroundStyle(.tint)
                                    .frame(width: 28)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(mode.name).foregroundStyle(.primary)
                                    Text(mode.summary).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(on ? Color.accentColor : Color.secondary)
                                    .font(.title3)
                            }
                        }
                    }
                } header: {
                    Text("Turn on a mode")
                } footer: {
                    Text("A mode you turn on here stays on until you turn it off, and wins over your schedule.")
                }

                Section("What each mode blocks") {
                    ForEach($engine.state.modes) { $mode in
                        NavigationLink {
                            ModeEditor(mode: $mode)
                        } label: {
                            Label(mode.name, systemImage: mode.symbol)
                        }
                    }
                }
            }
            .navigationTitle("Modes")
        }
    }
}

struct ModeEditor: View {
    @Binding var mode: FocusMode

    var body: some View {
        Form {
            Section("Name") {
                TextField("Name", text: $mode.name)
            }
            Section {
                ForEach(AppCategory.allCases) { category in
                    Toggle(isOn: Binding(
                        get: { mode.blocks.contains(category) },
                        set: { on in
                            if on { mode.blocks.insert(category) } else { mode.blocks.remove(category) }
                        })) {
                        Label(category.label, systemImage: category.symbol)
                    }
                }
            } header: {
                Text("Block these")
            } footer: {
                Text("Set each app's type in the Today tab.")
            }
        }
        .navigationTitle(mode.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: Schedule

struct ScheduleView: View {
    @EnvironmentObject private var engine: Engine
    @State private var editing: ScheduleBlock?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("Use my schedule", isOn: $engine.state.scheduleOn)
                } footer: {
                    Text("When on, modes switch on by themselves at these times, and you get a notification as each one starts.")
                }

                Section("Time blocks") {
                    if engine.state.blocks.isEmpty {
                        Text("No time blocks yet.").foregroundStyle(.secondary)
                    }
                    ForEach(sortedBlocks) { block in
                        Button { editing = block } label: { BlockRow(block: block) }
                    }
                    .onDelete { offsets in
                        let ids = offsets.map { sortedBlocks[$0].id }
                        engine.state.blocks.removeAll { ids.contains($0.id) }
                    }
                    Button {
                        editing = ScheduleBlock(modeID: "work", start: 9 * 60, end: 12 * 60, days: [2, 3, 4, 5, 6])
                    } label: {
                        Label("Add time block", systemImage: "plus")
                    }
                }
                .opacity(engine.state.scheduleOn ? 1 : 0.5)
            }
            .navigationTitle("Schedule")
            .sheet(item: $editing) { block in
                BlockEditor(draft: block) { saved in
                    if let i = engine.state.blocks.firstIndex(where: { $0.id == saved.id }) {
                        engine.state.blocks[i] = saved
                    } else {
                        engine.state.blocks.append(saved)
                    }
                }
            }
        }
    }

    private var sortedBlocks: [ScheduleBlock] {
        engine.state.blocks.sorted { $0.start < $1.start }
    }
}

struct BlockRow: View {
    @EnvironmentObject private var engine: Engine
    let block: ScheduleBlock

    var body: some View {
        let mode = engine.state.modes.first { $0.id == block.modeID }
        HStack(spacing: 12) {
            Image(systemName: mode?.symbol ?? "questionmark")
                .foregroundStyle(.tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(Clock.label(block.start)) – \(Clock.label(block.end))")
                    .foregroundStyle(.primary)
                Text("\(mode?.name ?? "Unknown mode") · \(block.daysLabel)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if engine.state.scheduleOn && block.contains(.now) {
                Text("NOW").font(.caption2.bold()).foregroundStyle(.green)
            }
        }
    }
}

struct BlockEditor: View {
    @EnvironmentObject private var engine: Engine
    @Environment(\.dismiss) private var dismiss
    @State var draft: ScheduleBlock
    let onSave: (ScheduleBlock) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Picker("Mode", selection: $draft.modeID) {
                    ForEach(engine.state.modes) { Label($0.name, systemImage: $0.symbol).tag($0.id) }
                }
                DatePicker("Starts", selection: time($draft.start), displayedComponents: .hourAndMinute)
                DatePicker("Ends", selection: time($draft.end), displayedComponents: .hourAndMinute)
                Section("Days") {
                    HStack {
                        ForEach(1...7, id: \.self) { day in
                            let on = draft.days.contains(day)
                            Button(Calendar.current.veryShortWeekdaySymbols[day - 1]) {
                                if on { draft.days.remove(day) } else { draft.days.insert(day) }
                            }
                            .frame(maxWidth: .infinity, minHeight: 36)
                            .background(on ? Color.accentColor : Color(.secondarySystemFill), in: Circle())
                            .foregroundStyle(on ? Color.white : Color.primary)
                        }
                    }
                    .buttonStyle(.plain)
                }
                if draft.end < draft.start {
                    Text("Ends the next morning.").font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Time block")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(draft)
                        dismiss()
                    }
                    .disabled(draft.days.isEmpty || draft.start == draft.end)
                }
            }
        }
    }

    private func time(_ minutes: Binding<Int>) -> Binding<Date> {
        Binding(
            get: { Clock.date(minutes.wrappedValue) },
            set: { minutes.wrappedValue = Clock.minutes($0) })
    }
}

// MARK: Setup

struct SetupView: View {
    @EnvironmentObject private var engine: Engine

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("iPhone apps can't see other apps on their own, so Focus Guard uses two Shortcuts automations per app: one when it opens, one when it closes. About a minute per app.")
                }

                Section("1 · When the app opens") {
                    Step(n: 1, "Open **Shortcuts** → **Automation** → **+** → **App**.")
                    Step(n: 2, "Choose the app (say Instagram), tick **Is Opened** only, and pick **Run Immediately**. Turn off **Notify When Run**.")
                    Step(n: 3, "Tap **Create New Shortcut** and add Focus Guard's **App Opened** action. Set App to the name below, e.g. **Instagram**.")
                    Step(n: 4, "Add an **If** action: If *App Opened* **is** `blocked`.")
                    Step(n: 5, "Inside the If, add **Go to Home Screen**. Tap Done.")
                }

                Section("2 · When the app closes") {
                    Step(n: 1, "New automation → **App** → same app → tick **Is Closed** only → **Run Immediately**.")
                    Step(n: 2, "Add Focus Guard's **App Closed** action with the same name. Done.")
                }

                Section("Names to use") {
                    ForEach(engine.state.apps) { app in
                        Label(app.name, systemImage: app.category.symbol)
                    }
                    Text("Add more apps on the Today tab, or just use a new name in Shortcuts and it's added automatically.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Top bar") {
                    Text("Settings → Focus Guard → turn on **Live Activities**. Then the counter shows on your Lock Screen and in the Dynamic Island.")
                }

                Section("Good to know") {
                    Text("Websites in Safari aren't counted. Only the apps are.")
                    Text("If iOS skips a \"closed\" event, one stretch counts for at most 90 minutes, and opening Focus Guard stops all timers.")
                    Text("Blocking sends you back to the Home Screen with a warning. You can still turn off an automation, so this is a strong nudge rather than a lock.")
                }
            }
            .navigationTitle("Setup")
        }
    }
}

struct Step: View {
    let n: Int
    let text: LocalizedStringKey

    init(n: Int, _ text: LocalizedStringKey) {
        self.n = n
        self.text = text
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(n)")
                .font(.caption.bold())
                .frame(width: 20, height: 20)
                .background(Color.accentColor.opacity(0.15), in: Circle())
            Text(text)
        }
    }
}
