// Focus Guard: you name a task and a duration; every window you switch to is
// checked against that task. Off-task windows get a warning popup, and if you
// come back to them after the grace period they get closed. Each finished
// session is written to a daily recap file in recaps/.
import http from "node:http";
import { spawn } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import readline from "node:readline";
import { fileURLToPath } from "node:url";
import Anthropic from "@anthropic-ai/sdk";

const here = path.dirname(fileURLToPath(import.meta.url));
const PORT = Number(process.env.FOCUS_GUARD_PORT || 4747);
const STATE_FILE = process.env.FOCUS_GUARD_STATE || path.join(here, "state.json");
const RECAP_DIR = process.env.FOCUS_GUARD_RECAPS || path.join(here, "recaps");
const MODEL = "claude-opus-5-5";
// Optional: link to your planner page; shows a Focus Guard | Focus Week switch in the app.
const FOCUS_WEEK_URL = process.env.FOCUS_WEEK_URL || "";
// "N minutes left" popups (override with e.g. FOCUS_GUARD_REMINDERS=10,2)
const REMINDERS_MIN = (process.env.FOCUS_GUARD_REMINDERS || "15,5").split(",").map(Number).filter((n) => n > 0);

const BROWSERS = new Set(["chrome", "msedge", "firefox", "brave", "opera", "vivaldi", "arc"]);
// Never judged or closed: system UI, and terminals (closing one could kill this monitor).
const PROTECTED = new Set([
  "", "idle", "explorer", "taskmgr", "searchhost", "searchapp", "startmenuexperiencehost",
  "shellexperiencehost", "lockapp", "windowsterminal", "powershell", "pwsh", "cmd",
  "conhost", "node", "openconsole",
]);
const NEUTRAL_TITLES = /^(new tab|new incognito tab|start page|untitled|about:blank|history|downloads|settings)$/i;
// Used only when no API key is set.
const DISTRACTIONS = [
  "youtube", "netflix", "hulu", "disney+", "prime video", "twitch", "tiktok", "instagram",
  "facebook", "reddit", "twitter", " / x", "discord", "steam", "epic games", "roblox",
  "spotify", "9gag", "pinterest", "snapchat", "crunchyroll", "espn", "amazon.com",
];

// ---------- state ----------
const fresh = () => ({ session: null, decisions: {}, warned: {}, log: [], stats: { checks: 0, warnings: 0, closes: 0 } });
let state = fresh();
try { state = { ...fresh(), ...JSON.parse(fs.readFileSync(STATE_FILE, "utf8")) }; } catch {}
let saveTimer = null;
function save() {
  clearTimeout(saveTimer);
  saveTimer = setTimeout(() => fs.writeFile(STATE_FILE, JSON.stringify(state, null, 1), () => {}), 300);
}
let current = null; // latest foreground window + verdict
let lastError = null;
const inFlight = new Map();
const closing = new Map(); // key -> time of last close attempt

function log(kind, entry) {
  state.log.unshift({ t: Date.now(), kind, ...entry });
  state.log.length = Math.min(state.log.length, 300);
  save();
}

// ---------- daily recap files (recaps/YYYY-MM-DD.json) ----------
const pad = (n) => String(n).padStart(2, "0");
const dayOf = (t) => { const d = new Date(t); return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`; };
const recapPath = (day) => path.join(RECAP_DIR, `${day}.json`);
function readRecap(day) {
  try { return JSON.parse(fs.readFileSync(recapPath(day), "utf8")); } catch { return { date: day, sessions: [] }; }
}
function writeRecap(r) {
  fs.mkdirSync(RECAP_DIR, { recursive: true });
  r.synced = false; // tells the sync job this day changed
  fs.writeFileSync(recapPath(r.date), JSON.stringify(r, null, 2));
}
function recordSession(rec) {
  const r = readRecap(dayOf(rec.startedAt));
  const i = r.sessions.findIndex((x) => x.id === rec.id);
  if (i >= 0) r.sessions[i] = rec; else r.sessions.push(rec);
  writeRecap(r);
}
function setOutcome(id, outcome) {
  // A session lives in the file for the day it started: check the last few days.
  for (let back = 0; back < 3; back++) {
    const r = readRecap(dayOf(Date.now() - back * 86_400_000));
    const s = r.sessions.find((x) => x.id === id);
    if (s) { s.outcome = outcome; s.answeredAt = Date.now(); writeRecap(r); return s; }
  }
  return null;
}

// ---------- window helper ----------
let helper = null;
function startHelper() {
  helper = process.env.FOCUS_GUARD_FAKE_HELPER // scripted window feed, for tests
    ? spawn(process.execPath, [process.env.FOCUS_GUARD_FAKE_HELPER])
    : spawn("powershell.exe", ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", path.join(here, "win-helper.ps1")], { windowsHide: true });
  readline.createInterface({ input: helper.stdout }).on("line", (line) => {
    let msg;
    try { msg = JSON.parse(line); } catch { return; }
    if (msg.type === "fg") onForeground(msg);
    else if (msg.type === "answer") onAnswer(msg);
    else if (msg.type === "error") lastError = `Window helper: ${msg.message}`;
  });
  helper.stderr.on("data", (d) => { lastError = `Window helper: ${String(d).trim()}`; });
  helper.on("exit", () => { helper = null; setTimeout(startHelper, 2000); });
}
const send = (cmd) => helper?.stdin.write(JSON.stringify(cmd) + "\n");

// ---------- classification ----------
function cleanTitle(title) {
  return title
    .replace(/\s+and \d+ more pages?/i, "")
    .replace(/\s*[-—]\s*(Google Chrome|Mozilla Firefox|Brave|Opera|Vivaldi|[^-—]*Microsoft​?\s?Edge)$/i, "")
    .replace(/^\(\d+\+?\)\s*/, "") // "(3) Inbox" unread counters
    .trim();
}
const keyOf = (w) => `${w.process.toLowerCase()}|${cleanTitle(w.title)}`;

function isIgnorable(w) {
  const proc = w.process.toLowerCase();
  const title = cleanTitle(w.title);
  if (PROTECTED.has(proc)) return true;
  if (!title || NEUTRAL_TITLES.test(title)) return true;
  if (/^focus guard/i.test(title)) return true; // the dashboard and its popups
  if (FOCUS_WEEK_URL && /focus week/i.test(title)) return true; // your planner, opened from the app
  const allow = state.session?.allow || [];
  return allow.some((a) => title.toLowerCase().includes(a) || proc === a);
}

const client = process.env.ANTHROPIC_API_KEY || process.env.ANTHROPIC_AUTH_TOKEN ? new Anthropic() : null;

const SYSTEM = `You guard a person's focus session. They committed to working on one task. You are shown the app and window title they just switched to, and you decide whether it is plausibly part of doing that task.

Allowed: anything that helps with the task - its tools (editors, IDEs, terminals, docs, references, Stack Overflow, AI assistants, course sites), searches about the task's subject, communication clearly about the task, and generic neutral screens.
Not allowed: entertainment, social media feeds, games, shopping, news, sports, and searches or pages on unrelated subjects.

Judge by meaning, not keywords: a YouTube tutorial on the task's subject is allowed; a music video is not. When a title is ambiguous but could reasonably be work, allow it - closing someone's work is worse than missing a distraction. Give a short reason (under 15 words) addressed to the person.`;

const SCHEMA = {
  type: "object",
  properties: { allowed: { type: "boolean" }, reason: { type: "string" } },
  required: ["allowed", "reason"],
  additionalProperties: false,
};

async function askClaude(task, w) {
  const params = {
    model: MODEL,
    max_tokens: 4000,
    system: SYSTEM,
    output_config: { effort: "low", format: { type: "json_schema", schema: SCHEMA } },
    messages: [{ role: "user", content: `Task: ${task}\nApp: ${w.process}\nWindow title: ${cleanTitle(w.title)}` }],
  };
  let res;
  try {
    // Server-side fallback reroutes the request if a safety classifier declines it.
    res = await client.beta.messages.create({ ...params, betas: ["server-side-fallback-2026-07-01"], fallbacks: "default" });
  } catch (err) {
    if (!(err instanceof Anthropic.BadRequestError)) throw err;
    res = await client.messages.create(params);
  }
  if (res.stop_reason === "refusal") return { allowed: true, reason: "Couldn't judge this one, so it's allowed." };
  const text = res.content.find((b) => b.type === "text")?.text;
  const out = JSON.parse(text);
  return { allowed: !!out.allowed, reason: String(out.reason || "") };
}

function keywordCheck(task, w) {
  const title = cleanTitle(w.title).toLowerCase();
  const words = task.toLowerCase().split(/\W+/).filter((x) => x.length > 3);
  if (words.some((x) => title.includes(x))) return { allowed: true, reason: "Mentions your task." };
  const hit = DISTRACTIONS.find((d) => title.includes(d) || w.process.toLowerCase().includes(d.trim()));
  if (hit) return { allowed: false, reason: `${hit.trim()} isn't part of your task.` };
  return { allowed: true, reason: "Not a known distraction (keyword mode)." };
}

function classify(key, w) {
  if (inFlight.has(key)) return;
  const task = state.session.task;
  const job = (async () => {
    try {
      const d = client ? await askClaude(task, w) : keywordCheck(task, w);
      lastError = null;
      return d;
    } catch (err) {
      lastError = `Claude check failed (${err.status ?? err.name}): ${err.message}. Using keyword rules.`;
      return keywordCheck(task, w);
    }
  })();
  inFlight.set(key, job);
  job.then((d) => {
    inFlight.delete(key);
    if (!state.session) return;
    state.decisions[key] = { ...d, title: cleanTitle(w.title), process: w.process };
    state.stats.checks++;
    log(d.allowed ? "allowed" : "flagged", { key, title: cleanTitle(w.title), process: w.process, reason: d.reason });
  });
}

// ---------- deadline ----------
function remindIfDue(s, now) {
  const left = s.endsAt - now;
  s.notified ||= {};
  for (const m of REMINDERS_MIN) {
    // Skip reminders that would fire right at the start of a short session.
    if (left <= m * 60_000 && !s.notified[m] && s.endsAt - s.startedAt > m * 90_000) {
      s.notified[m] = true;
      send({ cmd: "info", caption: "Focus Guard - time check", text: `${m} minutes left on:\n"${s.task}"\n\nWrap it up so you finish in time.` });
      log("session", { title: `${m} minutes left`, reason: s.task });
    }
  }
}

// ---------- the main rule ----------
function onForeground(w) {
  const now = Date.now();
  const s = state.session;
  current = { ...w, cleanTitle: cleanTitle(w.title), verdict: "idle", reason: "" };
  if (!s) return;
  if (now >= s.endsAt) return endSession("pending");
  remindIfDue(s, now);
  const dt = Math.min(5, (now - (s.lastTick || now)) / 1000); // seconds since last tick
  s.lastTick = now;
  if (isIgnorable(w)) { current.verdict = "ignored"; return; }

  const key = keyOf(w);
  const d = state.decisions[key];
  if (!d) { current.verdict = "checking"; classify(key, w); return; }
  current.verdict = d.allowed ? "on-task" : "off-task";
  current.reason = d.reason;
  if (d.allowed) {
    s.focusSec = (s.focusSec || 0) + dt;
    s.windows ||= {};
    s.windows[d.title] = (s.windows[d.title] || 0) + dt;
    return;
  }

  const warnedAt = state.warned[key];
  if (!warnedAt) {
    state.warned[key] = now;
    state.stats.warnings++;
    log("warned", { key, title: d.title, process: w.process, reason: d.reason });
    send({
      cmd: "warn",
      caption: "Focus Guard - this is not allowed",
      text: `WARNING: this is not allowed.\n\n"${d.title}" isn't part of your task:\n"${s.task}"\n\n${d.reason}\n\nClose it now. If it's still open in ${s.grace} seconds, Focus Guard will close it for you.`,
    });
    return;
  }

  const left = Math.ceil((warnedAt + s.grace * 1000 - now) / 1000);
  if (left > 0) { current.countdown = left; return; }
  if (now - (closing.get(key) || 0) < 3000) return; // give the last close a moment to land
  closing.set(key, now);
  const browser = BROWSERS.has(w.process.toLowerCase());
  send({ cmd: "close", hwnd: w.hwnd, mode: browser ? "tab" : "window" });
  state.stats.closes++;
  log("closed", { key, title: d.title, process: w.process, reason: browser ? "Closed the tab." : "Closed the window." });

  if (!browser) {
    // Apps can refuse a polite close (e.g. "minimize to tray"). Force it if it's still up.
    setTimeout(() => {
      if (current && current.pid === w.pid && keyOf(current) === key && state.session) {
        send({ cmd: "kill", pid: w.pid });
        log("closed", { key, title: d.title, process: w.process, reason: "Ignored the close, so the app was force-quit." });
      }
    }, 4000);
  }
}

// outcome: "done" (finished early), "quit" (gave up), "pending" (time ran out: ask)
function endSession(outcome) {
  const s = state.session;
  if (!s) return;
  const now = Date.now();
  const top = Object.entries(s.windows || {}).sort((a, b) => b[1] - a[1]).slice(0, 3);
  const rec = {
    id: s.id || now.toString(36),
    task: s.task,
    startedAt: s.startedAt,
    endedAt: now,
    plannedMin: Math.round((s.endsAt - s.startedAt) / 60_000),
    focusedMin: Math.round((s.focusSec || 0) / 60),
    outcome,
    warnings: state.stats.warnings,
    closes: state.stats.closes,
    mainWindows: top.map(([title, sec]) => ({ title, min: Math.round(sec / 60) })),
  };
  recordSession(rec);
  const labels = { done: "finished", quit: "ended early", pending: "time's up" };
  log("session", { title: `Session ${labels[outcome]}: ${s.task}`, reason: `${rec.focusedMin} min focused, ${rec.warnings} warnings, ${rec.closes} closes` });
  if (outcome === "pending") {
    send({ cmd: "ask", id: rec.id, caption: "Focus Guard - time's up", text: `Time's up.\n\nDid you finish:\n"${s.task}"?` });
  }
  state.session = null;
  state.warned = {};
  state.decisions = {};
  save();
}

function onAnswer({ id, yes }) {
  const s = setOutcome(id, yes ? "done" : "not done");
  if (s) log("session", { title: yes ? `Finished: ${s.task}` : `Not finished: ${s.task}`, reason: yes ? "Nice. It'll be checked off in Focus Week tonight." : "It'll stay on your Focus Week board." });
}

// ---------- HTTP ----------
const QUIT_PHRASE = "i am choosing to quit";

function body(req) {
  return new Promise((resolve) => {
    let b = "";
    req.on("data", (c) => (b += c));
    req.on("end", () => { try { resolve(JSON.parse(b || "{}")); } catch { resolve({}); } });
  });
}
function json(res, code, obj) {
  res.writeHead(code, { "content-type": "application/json; charset=utf-8" });
  res.end(JSON.stringify(obj));
}

http.createServer(async (req, res) => {
  const url = new URL(req.url, `http://localhost:${PORT}`);
  if (req.method === "GET" && url.pathname === "/") {
    res.writeHead(200, { "content-type": "text/html; charset=utf-8" });
    return fs.createReadStream(path.join(here, "public", "index.html")).pipe(res);
  }
  if (req.method === "GET" && (url.pathname === "/favicon.ico" || url.pathname === "/icon.png")) {
    const file = url.pathname === "/icon.png" ? path.join(here, "public", "icon.png") : path.join(here, "focus-guard.ico");
    if (!fs.existsSync(file)) return json(res, 404, { error: "No icon yet (run make-icon.ps1)." });
    res.writeHead(200, { "content-type": url.pathname === "/icon.png" ? "image/png" : "image/x-icon", "cache-control": "max-age=3600" });
    return fs.createReadStream(file).pipe(res);
  }
  if (req.method === "GET" && url.pathname === "/api/state") {
    return json(res, 200, {
      session: state.session, stats: state.stats, log: state.log.slice(0, 100),
      current, mode: client ? "claude" : "keywords", error: lastError, helper: !!helper, now: Date.now(),
      today: readRecap(dayOf(Date.now())), focusWeekUrl: FOCUS_WEEK_URL,
    });
  }
  if (req.method === "POST" && url.pathname === "/api/start") {
    const b = await body(req);
    const task = String(b.task || "").trim();
    const minutes = Number(b.hours || 0) * 60 + Number(b.minutes || 0);
    if (!task || !(minutes > 0)) return json(res, 400, { error: "Give a task and a duration." });
    if (state.session) return json(res, 409, { error: "A session is already running." });
    const now = Date.now();
    state.session = {
      id: now.toString(36), task, startedAt: now, endsAt: now + minutes * 60_000,
      grace: Math.max(5, Math.min(300, Number(b.grace) || 20)),
      allow: String(b.allow || "").split(",").map((x) => x.trim().toLowerCase()).filter(Boolean),
      notified: {}, focusSec: 0, windows: {},
    };
    state.decisions = {};
    state.warned = {};
    state.stats = { checks: 0, warnings: 0, closes: 0 };
    log("session", { title: `Session started: ${task}`, reason: `${Math.round(minutes)} min` });
    return json(res, 200, { ok: true });
  }
  if (req.method === "POST" && url.pathname === "/api/finish") {
    if (!state.session) return json(res, 400, { error: "No session running." });
    endSession("done");
    return json(res, 200, { ok: true });
  }
  if (req.method === "POST" && url.pathname === "/api/stop") {
    const b = await body(req);
    if (String(b.phrase || "").trim().toLowerCase() !== QUIT_PHRASE) return json(res, 400, { error: `Type "${QUIT_PHRASE}" to end early.` });
    endSession("quit");
    return json(res, 200, { ok: true });
  }
  if (req.method === "POST" && url.pathname === "/api/outcome") {
    // Answer "did you finish?" from the dashboard (if the popup was missed) or change it.
    const b = await body(req);
    if (!["done", "not done"].includes(b.outcome)) return json(res, 400, { error: "Outcome must be done or not done." });
    const s = setOutcome(String(b.id), b.outcome);
    return s ? json(res, 200, { ok: true }) : json(res, 404, { error: "Unknown session." });
  }
  if (req.method === "POST" && url.pathname === "/api/allow") {
    // The checker got it wrong: mark this window as on-task for the rest of the session.
    const b = await body(req);
    const d = state.decisions[b.key];
    if (!d) return json(res, 404, { error: "Unknown window." });
    state.decisions[b.key] = { ...d, allowed: true, reason: "You marked this as on-task." };
    delete state.warned[b.key];
    log("allowed", { key: b.key, title: d.title, process: d.process, reason: "You marked this as on-task." });
    return json(res, 200, { ok: true });
  }
  json(res, 404, { error: "Not found" });
}).listen(PORT, "127.0.0.1", () => {
  console.log(`Focus Guard dashboard: http://localhost:${PORT}`);
  console.log(client ? `Relevance checks: Claude (${MODEL})` : "Relevance checks: keyword rules (set ANTHROPIC_API_KEY in .env for smart checks)");
  startHelper();
});
