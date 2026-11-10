# Focus Guard

A Windows focus enforcer. Tell it what you're working on and for how long. While the session
runs, every window you switch to (including each browser tab and Google search, by its title)
is checked against your task:

- **Off-task** → a "WARNING: this is not allowed" popup, with N seconds to comply.
- **Still there (or you come back to it) after that** → it closes it: the tab (Ctrl+W) for
  browsers, the window for apps, and a force-quit if the app refuses to close.
- **Finishing on time** → "15 / 5 minutes left" reminders, and when time's up a popup asks
  *Did you finish?* (or press **I finished** to end early).
- **Daily recap** → every session (task, result, focused minutes, main windows) is written to
  `recaps/YYYY-MM-DD.json`, ready to sync into a planner.

Relevance is judged by Claude (window title + your task, nothing else), with a keyword
fallback when no API key is set.

## Install

Needs Windows 10/11 and Node.js 22+.

```
npm install
copy .env.example .env      # then add your Anthropic API key
powershell -ExecutionPolicy Bypass -File install.ps1
```

`install.ps1` creates a **Focus Guard** icon on the desktop and Start menu (click to open the
app in its own window) and starts the server hidden at login. Use `-NoStartup` to skip
auto-start. To run it by hand instead: `npm start`, then open http://localhost:4747.

## Settings (`.env`)

| Name | What it does |
| --- | --- |
| `ANTHROPIC_API_KEY` | Smart relevance checks with Claude. Without it, only known distractions are blocked. |
| `FOCUS_WEEK_URL` | Optional link to your planner; adds a Focus Guard / Focus Week switch to the app. |
| `FOCUS_GUARD_PORT` | Dashboard port (default 4747). |
| `FOCUS_GUARD_REMINDERS` | Minutes-left reminders (default `15,5`). |

## What it sees and sends

- Reads only the **active window's title and app name**, once a second. No screenshots, no
  page contents, no keystrokes.
- Sends Claude one short message per new title: your task, the app name and the title.
  Terminals, File Explorer, the dashboard and anything on your "always allowed" list are
  never sent.
- Everything else (log, decisions, recaps) stays in `state.json` and `recaps/` on your machine.

## How it works

| File | Role |
| --- | --- |
| `server.js` | Dashboard + API, relevance checks, warn/close rules, recaps |
| `win-helper.ps1` | Reports the foreground window; shows popups; closes tabs/windows |
| `public/index.html` | Dashboard |
| `launch.ps1`, `start-hidden.ps1`, `install.ps1` | App launcher, hidden start, shortcuts |
| `make-icon.ps1` | Draws the icon |

Terminals, File Explorer, Task Manager and system UI are never closed. If it misjudges
something, click **Actually on-task** in the activity list. Ending early without finishing
requires typing `i am choosing to quit`.

## Syncing recaps to a planner

Each `recaps/*.json` file has `"synced": false` until something consumes it. A nightly job
(e.g. a scheduled Claude task) can read unsynced files, tick off or add matching items in your
planner, post a summary, and set `"synced": true`.

## iPhone version

[`ios/`](ios/README.md) has a phone version: per-app usage in the Lock Screen / Dynamic Island,
blocking modes (No social media, No gaming, Work, Fun, Relax) and a schedule. It works with a free
Apple ID via Shortcuts automations and SideStore.
