import AppIntents

/// Lets the Shortcuts editor offer the tracked app names as choices.
struct TrackedAppOptions: DynamicOptionsProvider {
    func results() async throws -> [String] {
        await MainActor.run { Engine.shared.state.apps.map(\.name) }
    }
}

/// Shortcuts automation: "When Instagram is opened" -> App Opened (Instagram).
/// Returns "blocked" or "allowed" so the automation can send you to the Home Screen.
struct AppOpenedIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "App Opened"
    static var description = IntentDescription(
        "Tells Focus Guard an app was opened. Returns \"blocked\" when the current mode blocks it, otherwise \"allowed\".")

    @Parameter(title: "App", optionsProvider: TrackedAppOptions())
    var app: String

    static var parameterSummary: some ParameterSummary {
        Summary("\(\.$app) was opened")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let blocked = await Engine.shared.appOpened(app)
        return .result(value: blocked ? "blocked" : "allowed")
    }
}

/// Shortcuts automation: "When Instagram is closed" -> App Closed (Instagram).
struct AppClosedIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "App Closed"
    static var description = IntentDescription("Tells Focus Guard an app was closed, so it stops counting its time.")

    @Parameter(title: "App", optionsProvider: TrackedAppOptions())
    var app: String

    static var parameterSummary: some ParameterSummary {
        Summary("\(\.$app) was closed")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        await Engine.shared.appClosed(app)
        return .result()
    }
}
