# Focus Guard for iPhone

The phone version of Focus Guard:

- **Usage counter in the top bar.** Time on each app shows on the Lock Screen and in the Dynamic Island. It ticks live while the app is open and otherwise goes up in 5-minute steps.
- **Modes.** No social media, No gaming, Work, Fun and Relax. Each mode blocks app types you choose. When you open a blocked app you get "Warning: this is not allowed" and are sent back to the Home Screen.
- **Schedule.** A toggle plus time blocks (for example Work 9–12 on weekdays) that switch modes on by themselves.

It needs no paid Apple Developer account. iPhone apps can't see other apps without Apple's paid-only Screen Time API, so Focus Guard learns about app opens and closes from **Shortcuts automations** that you add once per app.

## Limits

- Only apps are counted. Websites in Safari aren't, because Shortcuts can't see them.
- Blocking is a strong nudge, not a lock. You can always turn an automation off.
- If iOS skips a "closed" event, a single stretch counts for at most 90 minutes. Opening Focus Guard stops all timers.

## Build (Mac)

1. Install Xcode from the App Store, then run `brew install xcodegen` in Terminal.
2. Copy this `ios` folder to the Mac, or clone the repo.
3. Run `./build-ipa.sh`. It creates `FocusGuard.ipa`.

To try it quickly instead, run `xcodegen` and open `FocusGuard.xcodeproj`. Sign in under Xcode → Settings → Accounts, pick your Personal Team in Signing & Capabilities for both targets, plug in the iPhone and press Run. Builds installed this way stop working after 7 days.

## Install without the 7-day reinstall

A free Apple ID signs apps for only 7 days. [SideStore](https://sidestore.io) re-signs them on the phone, so you don't need to plug in again.

1. Install SideStore by following its official guide. It needs your Mac once, to create a pairing file.
2. AirDrop `FocusGuard.ipa` to the iPhone and open it with SideStore. Sign in with your Apple ID when SideStore asks.
3. Make SideStore refresh by itself. In Shortcuts → Automation, add a daily automation (for example at 3 AM, or when the phone starts charging) that runs SideStore's **Refresh All Apps**. SideStore's docs explain the VPN step this needs on your iOS version.

Check SideStore now and then. Community guides say the automatic refresh is sometimes flaky. If an app is about to expire, open SideStore and tap Refresh.

## Set up on the phone

1. Open Focus Guard and allow notifications.
2. Turn on Live Activities: Settings → Focus Guard → Live Activities.
3. Follow the app's **Setup** tab. For each app, add two Shortcuts automations:
   - **App, Is Opened, Run Immediately.** Use the Focus Guard **App Opened** action with the app's name. Then add `If App Opened is "blocked"` → **Go to Home Screen**.
   - **App, Is Closed, Run Immediately.** Use the Focus Guard **App Closed** action with the same name.
4. In the **Modes** tab, choose what each mode blocks. In the **Schedule** tab, add time blocks and turn on "Use my schedule".
