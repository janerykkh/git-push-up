// git push-up: eine zufällige Übung pro Wartepause.
"use strict";

const $ = (id) => document.getElementById(id);
const byId = Object.fromEntries(EXERCISES.map((e) => [e.id, e]));

/* ---------------- Speicher ---------------- */
const KEY = { log: "gpu-log", deleted: "gpu-deleted", last: "gpu-lastcat", backup: "gpu-backup", equip: "gpu-equip" };
function load(k, fallback) { try { const v = localStorage.getItem(k); return v ? JSON.parse(v) : fallback; } catch (e) { return fallback; } }
function save(k, v) { try { localStorage.setItem(k, JSON.stringify(v)); } catch (e) {} }

let log = load(KEY.log, []);
let deleted = load(KEY.deleted, []);
let lastCat = load(KEY.last, null);
let backupCfg = load(KEY.backup, { repo: "janerykkh/git-push-up-private", token: "", last: 0 });
let equipOn = load(KEY.equip, {});

if (navigator.storage && navigator.storage.persist) navigator.storage.persist().catch(() => {});

function persistLog() { save(KEY.log, log); }
function uid() { return Date.now().toString(36) + Math.random().toString(36).slice(2, 8); }

/* ---------------- Ziel-Logik ---------------- */
function targetFor(ex) {
  for (let i = log.length - 1; i >= 0; i--) {
    const l = log[i];
    if (l.ex !== ex.id) continue;
    if (l.done) return l.target + ex.step;
    return Math.max(ex.unit === "sec" ? 10 : 1, l.actual);
  }
  return ex.base;
}
function unitsOf(entry) {
  const ex = byId[entry.ex];
  if (!ex) return 0;
  let u = ex.unit === "sec" ? entry.actual / SECONDS_PER_REP : entry.actual;
  if (ex.side) u *= 2;
  return u;
}

/* ---------------- Bildschirme ---------------- */
const SCREENS = ["home", "exercise", "done", "stats", "settings"];
function show(name) {
  SCREENS.forEach((s) => ($(s).hidden = s !== name));
  window.scrollTo(0, 0);
  if (name === "home") renderHome();
  if (name === "stats") renderStats();
  if (name === "settings") renderSettings();
}

/* ---------------- Start ---------------- */
function startOfDay(t = Date.now()) { const d = new Date(t); d.setHours(0, 0, 0, 0); return d.getTime(); }
function streak() {
  const days = new Set(log.map((l) => startOfDay(l.ts)));
  let d = startOfDay();
  if (!days.has(d)) d -= 864e5;
  let n = 0;
  while (days.has(d)) { n++; d = startOfDay(d - 12 * 36e5); }
  return n;
}
function renderHome() {
  const today = log.filter((l) => l.ts >= startOfDay()).length;
  const s = streak();
  if (!log.length) { $("homeInfo").textContent = "Bereit, wenn dein Build es ist."; return; }
  const parts = [`Heute ${today} ${today === 1 ? "Übung" : "Übungen"}`];
  if (s > 1) parts.push(`Serie ${s} Tage`);
  $("homeInfo").textContent = parts.join(" · ");
}

/* ---------------- Übung ---------------- */
let current = null, timer = null, anim = 0;

function pool() {
  return EXERCISES.filter((e) => !e.equipment || equipOn[e.equipment]);
}
function pick(excludeCats, excludeId) {
  const all = pool();
  let p = all.filter((e) => !excludeCats.includes(e.cat) && e.id !== excludeId);
  if (!p.length) p = all.filter((e) => e.id !== excludeId);
  if (!p.length) p = all;
  return p[Math.floor(Math.random() * p.length)];
}
function startExercise(ex) {
  stopTimer();
  current = { ex, target: targetFor(ex) };
  const el = $("exercise");
  el.style.setProperty("--c", `var(--${ex.cat})`);
  $("exCat").textContent = CATEGORIES[ex.cat].label;
  $("exName").textContent = ex.name;
  $("exTarget").textContent = current.target;
  $("exUnit").textContent = (ex.unit === "sec" ? "Sekunden halten" : "Wiederholungen") + (ex.side ? " pro Seite" : "");
  $("exCue").textContent = ex.cue;
  $("exNote").hidden = !ex.note; $("exNote").textContent = ex.note || "";
  $("timerRow").hidden = ex.unit !== "sec"; $("timerVal").textContent = "0 s"; $("timerBtn").textContent = "Timer starten";
  $("doneRow").hidden = false; $("partialForm").hidden = true; $("skipBtn").hidden = false;
  $("partialLabel").textContent = ex.unit === "sec" ? "Wie viele Sekunden hast du gehalten?" : "Wie viele Wiederholungen hast du geschafft?";
  $("partialIn").value = "";
  drawFigure(ex);
  show("exercise");
}

$("goBtn").onclick = () => startExercise(pick([lastCat], null));
$("skipBtn").onclick = () => startExercise(pick([lastCat, current.ex.cat], current.ex.id));
$("exClose").onclick = () => { stopTimer(); show("home"); };
$("okBtn").onclick = () => finish(true, current.target);
$("noBtn").onclick = () => { stopTimer(); $("doneRow").hidden = true; $("skipBtn").hidden = true; $("partialForm").hidden = false; setTimeout(() => $("partialIn").focus(), 50); };
$("partialForm").addEventListener("submit", (e) => { e.preventDefault(); finish(false, Math.max(0, parseInt($("partialIn").value, 10) || 0)); });

function finish(done, actual) {
  stopTimer();
  const { ex, target } = current;
  log.push({ id: uid(), ex: ex.id, cat: ex.cat, target, actual, done, ts: Date.now() });
  persistLog();
  lastCat = ex.cat; save(KEY.last, lastCat);
  const u = ex.unit === "sec" ? " s" : "";
  const side = ex.side ? " pro Seite" : "";
  $("doneIcon").className = done ? "check" : "check partly";
  $("doneIcon").textContent = done ? "✓" : "↗";
  $("doneText").textContent = done ? `${target}${u} ${ex.name}${side}` : `${actual} von ${target}${u} ${ex.name}`;
  show("done");
  setTimeout(() => { if (!$("done").hidden) show("home"); }, 1500);
  maybeAutoBackup();
}
$("done").onclick = () => show("home");

function stopTimer() { if (timer) { clearInterval(timer); timer = null; } }
$("timerBtn").onclick = () => {
  if (timer) { stopTimer(); $("timerBtn").textContent = "Timer starten"; return; }
  const t0 = Date.now();
  $("timerBtn").textContent = "Stopp";
  timer = setInterval(() => {
    const s = Math.floor((Date.now() - t0) / 1000);
    $("timerVal").textContent = s >= current.target ? `${s} s ✓` : `${s} s`;
    $("partialIn").value = s;
  }, 250);
};

/* ---------------- Strichfigur ---------------- */
const LIMBS = [[1,2],[2,3],[3,4],[2,5],[5,6],[1,7],[7,8],[1,9],[9,10]];
function drawFigure(ex) {
  cancelAnimationFrame(anim);
  const lines = LIMBS.map((_, i) => `<line stroke-width="${i >= 7 ? 6 : 7}" stroke-linecap="round"/>`).join("");
  $("figure").innerHTML = `<svg viewBox="0 0 240 165" role="img" aria-label="Animation: ${ex.name}">
    <line x1="10" y1="152" x2="230" y2="152" stroke="var(--line)" stroke-width="3" stroke-linecap="round"/>
    <g stroke="var(--${ex.cat})" fill="none">${lines}<circle r="10" stroke-width="5" fill="var(--surface)"/></g></svg>`;
  const svg = $("figure").querySelector("svg");
  const ls = svg.querySelectorAll("g line"), head = svg.querySelector("circle");
  const reduce = matchMedia("(prefers-reduced-motion: reduce)").matches;
  const period = ex.unit === "sec" ? 4200 : 2400;
  const t0 = performance.now();
  function frame(now) {
    if (!svg.isConnected) return;
    const ph = ((now - t0) % period) / period;
    let p;
    if (reduce) p = 1;
    else if (ex.unit === "sec") { const q = ph < 0.2 ? ph / 0.2 : ph < 0.8 ? 1 : 1 - (ph - 0.8) / 0.2; p = (1 - Math.cos(q * Math.PI)) / 2; }
    else p = (1 - Math.cos(ph * 2 * Math.PI)) / 2;
    const P = ex.a.map((q, i) => [q[0] + (ex.b[i][0] - q[0]) * p, q[1] + (ex.b[i][1] - q[1]) * p]);
    LIMBS.forEach(([a, b], i) => {
      ls[i].setAttribute("x1", P[a][0]); ls[i].setAttribute("y1", P[a][1]);
      ls[i].setAttribute("x2", P[b][0]); ls[i].setAttribute("y2", P[b][1]);
    });
    const n = P[1], h = P[0], dx = h[0] - n[0], dy = h[1] - n[1], d = Math.hypot(dx, dy) || 1;
    head.setAttribute("cx", n[0] + (dx / d) * 12); head.setAttribute("cy", n[1] + (dy / d) * 12);
    if (!reduce) anim = requestAnimationFrame(frame);
  }
  anim = requestAnimationFrame(frame);
}

/* ---------------- Statistik ---------------- */
let period = "day", selMuscle = null;
const MONTHS = ["Jan","Feb","Mär","Apr","Mai","Jun","Jul","Aug","Sep","Okt","Nov","Dez"];
const WD = ["Mo","Di","Mi","Do","Fr","Sa","So"];

function periodRange(p) {
  const now = new Date();
  const s = new Date(now); s.setHours(0, 0, 0, 0);
  if (p === "week") s.setDate(s.getDate() - ((s.getDay() + 6) % 7));
  if (p === "month") s.setDate(1);
  if (p === "year") { s.setMonth(0, 1); }
  return s.getTime();
}
function inPeriod() { const s = periodRange(period); return log.filter((l) => l.ts >= s); }

$("periodSeg").addEventListener("click", (e) => {
  const b = e.target.closest("button[data-p]"); if (!b) return;
  period = b.dataset.p;
  $("periodSeg").querySelectorAll("button").forEach((x) => x.setAttribute("aria-selected", x === b ? "true" : "false"));
  renderStats();
});
$("toStats").onclick = () => show("stats");
$("statsBack").onclick = () => show("home");
$("toSettings").onclick = () => show("settings");
$("settingsBack").onclick = () => show("stats");

function muscleLoad(entries) {
  const load = Object.fromEntries(Object.keys(MUSCLES).map((m) => [m, 0]));
  entries.forEach((l) => {
    const ex = byId[l.ex]; if (!ex) return;
    const u = unitsOf(l);
    Object.entries(ex.muscles).forEach(([m, w]) => { if (m in load) load[m] += u * w; });
  });
  return load;
}

// Körpermodell: Vorder- und Rückansicht, Muskeln als einfache Formen
const BODY = {
  front: {
    neutral: [
      ["circle", { cx: 100, cy: 32, r: 17 }], ["rect", { x: 92, y: 48, width: 16, height: 12, rx: 4 }],
      ["ellipse", { cx: 44, cy: 162, rx: 7, ry: 22 }, true], ["circle", { cx: 41, cy: 192, r: 6 }, true],
      ["ellipse", { cx: 100, cy: 188, rx: 27, ry: 12 }],
      ["ellipse", { cx: 87, cy: 304, rx: 9, ry: 30 }, true], ["ellipse", { cx: 86, cy: 341, rx: 11, ry: 5 }, true],
    ],
    muscles: [
      ["frontDelt", "ellipse", { cx: 64, cy: 78, rx: 13, ry: 12 }, true],
      ["chest", "ellipse", { cx: 84, cy: 95, rx: 16, ry: 13 }, true],
      ["biceps", "ellipse", { cx: 52, cy: 119, rx: 8, ry: 19 }, true],
      ["abs", "rect", { x: 88, y: 110, width: 24, height: 66, rx: 8 }],
      ["obliques", "ellipse", { cx: 76, cy: 145, rx: 8, ry: 24 }, true],
      ["quads", "ellipse", { cx: 87, cy: 234, rx: 13, ry: 40 }, true],
    ],
  },
  back: {
    neutral: [
      ["circle", { cx: 100, cy: 32, r: 17 }], ["rect", { x: 92, y: 48, width: 16, height: 12, rx: 4 }],
      ["ellipse", { cx: 44, cy: 162, rx: 7, ry: 22 }, true], ["circle", { cx: 41, cy: 192, r: 6 }, true],
      ["ellipse", { cx: 86, cy: 341, rx: 11, ry: 5 }, true],
    ],
    muscles: [
      ["upperBack", "polygon", { points: "100,58 128,72 117,110 100,118 83,110 72,72" }],
      ["rearDelt", "ellipse", { cx: 63, cy: 78, rx: 12, ry: 12 }, true],
      ["triceps", "ellipse", { cx: 52, cy: 119, rx: 8, ry: 19 }, true],
      ["lats", "ellipse", { cx: 80, cy: 130, rx: 11, ry: 25 }, true],
      ["lowerBack", "rect", { x: 88, y: 132, width: 24, height: 38, rx: 8 }],
      ["glutes", "ellipse", { cx: 88, cy: 192, rx: 14, ry: 16 }, true],
      ["hamstrings", "ellipse", { cx: 87, cy: 245, rx: 12, ry: 32 }, true],
      ["calves", "ellipse", { cx: 87, cy: 303, rx: 10, ry: 27 }, true],
    ],
  },
};
function mirrorAttrs(tag, a) {
  const m = { ...a };
  if ("cx" in m) m.cx = 200 - m.cx;
  if (tag === "rect") m.x = 200 - m.x - m.width;
  return m;
}
function shape(tag, a, cls, extra = "") {
  return `<${tag} class="${cls}" ${Object.entries(a).map(([k, v]) => `${k}="${v}"`).join(" ")} ${extra}/>`;
}
function renderBody(load) {
  const max = Math.max(...Object.values(load));
  const fill = (m) => {
    const r = max > 0 ? load[m] / max : 0;
    const pct = r > 0 ? Math.round(18 + 82 * r) : 0;
    return `fill:color-mix(in oklch, var(--muscle-base), var(--muscle-hot) ${pct}%)`;
  };
  const view = (v, dx, label) => {
    let s = `<g transform="translate(${dx},0)">`;
    BODY[v].neutral.forEach(([tag, a, mir]) => {
      s += shape(tag, a, "n");
      if (mir) s += shape(tag, mirrorAttrs(tag, a), "n");
    });
    BODY[v].muscles.forEach(([m, tag, a, mir]) => {
      const cls = "m" + (selMuscle === m ? " sel" : "");
      const ex = `data-m="${m}" style="${fill(m)}"`;
      s += shape(tag, a, cls, ex);
      if (mir) s += shape(tag, mirrorAttrs(tag, a), cls, ex);
    });
    s += `<text x="100" y="366">${label}</text></g>`;
    return s;
  };
  $("bodyMap").innerHTML = `<svg viewBox="0 0 400 376" role="img" aria-label="Körpermodell mit trainierten Muskeln">${view("front", 0, "Vorne")}${view("back", 200, "Hinten")}</svg>`;
  $("bodyMap").querySelectorAll(".m").forEach((el) => el.addEventListener("click", () => {
    selMuscle = el.dataset.m; renderStats();
  }));
  if (selMuscle) {
    const r = max > 0 ? Math.round((load[selMuscle] / max) * 100) : 0;
    const hitters = EXERCISES.filter((e) => e.muscles[selMuscle]).sort((a, b) => b.muscles[selMuscle] - a.muscles[selMuscle]).map((e) => e.name);
    $("muscleInfo").textContent = `${MUSCLES[selMuscle]}: ${r} % vom meisttrainierten Muskel. ` +
      (hitters.length ? `Trainiert durch: ${hitters.slice(0, 3).join(", ")}.` : "Keine Übung im Pool trifft diesen Muskel.");
  } else {
    $("muscleInfo").textContent = "Je grüner, desto mehr hat der Muskel im Zeitraum gearbeitet, im Vergleich zum meisttrainierten.";
  }
  const weak = max > 0 ? Object.keys(MUSCLES).filter((m) => load[m] / max < 0.15) : [];
  $("weak").innerHTML = weak.length ? `<span class="small" style="flex-basis:100%">Kaum trainiert:</span>` + weak.map((m) => `<span class="chip">${MUSCLES[m]}</span>`).join("") : "";
}

function renderChart(entries) {
  const s = periodRange(period);
  let buckets, labels, labelEvery;
  if (period === "day") {
    buckets = new Array(24).fill(0); labels = buckets.map((_, i) => `${i}`); labelEvery = 6;
    entries.forEach((l) => buckets[new Date(l.ts).getHours()]++);
    $("chartTitle").textContent = "Übungen nach Uhrzeit";
  } else if (period === "week") {
    buckets = new Array(7).fill(0); labels = WD; labelEvery = 1;
    entries.forEach((l) => buckets[Math.floor((startOfDay(l.ts) - s) / 864e5 + 0.5)]++);
    $("chartTitle").textContent = "Übungen pro Tag";
  } else if (period === "month") {
    const d = new Date(s); const n = new Date(d.getFullYear(), d.getMonth() + 1, 0).getDate();
    buckets = new Array(n).fill(0); labels = buckets.map((_, i) => `${i + 1}`); labelEvery = 7;
    entries.forEach((l) => buckets[new Date(l.ts).getDate() - 1]++);
    $("chartTitle").textContent = "Übungen pro Tag";
  } else {
    buckets = new Array(12).fill(0); labels = MONTHS; labelEvery = 2;
    entries.forEach((l) => buckets[new Date(l.ts).getMonth()]++);
    $("chartTitle").textContent = "Übungen pro Monat";
  }
  const W = 320, H = 130, pad = 18, top = 14;
  const max = Math.max(1, ...buckets);
  const bw = (W - 8) / buckets.length;
  let svg = `<svg viewBox="0 0 ${W} ${H + pad}" role="img" aria-label="${$("chartTitle").textContent}">`;
  svg += `<line x1="0" y1="${H}" x2="${W}" y2="${H}" stroke="var(--line)"/>`;
  svg += `<line x1="0" y1="${top}" x2="${W}" y2="${top}" stroke="var(--line)" stroke-dasharray="2 4"/><text x="${W}" y="${top - 3}" text-anchor="end">${max}</text>`;
  buckets.forEach((v, i) => {
    const h = (v / max) * (H - top);
    const x = 4 + i * bw + bw * 0.15;
    if (v) svg += `<rect x="${x}" y="${H - h}" width="${bw * 0.7}" height="${h}" rx="2" fill="var(--accent)"/>`;
    if (i % labelEvery === 0) svg += `<text x="${4 + i * bw + bw / 2}" y="${H + 13}" text-anchor="middle">${labels[i]}</text>`;
  });
  svg += "</svg>";
  $("chart").innerHTML = svg;
}

function fmtTime(ts) {
  const d = new Date(ts);
  return d.toLocaleDateString("de-DE", { day: "2-digit", month: "2-digit" }) + ", " + d.toLocaleTimeString("de-DE", { hour: "2-digit", minute: "2-digit" });
}

function renderStats() {
  const entries = inPeriod();
  const doneN = entries.filter((l) => l.done).length;
  const days = new Set(entries.map((l) => startOfDay(l.ts))).size;
  const reps = Math.round(entries.reduce((a, l) => a + unitsOf(l), 0));
  const kpi = (v, l) => `<div class="kpi"><b>${v}</b>${l}</div>`;
  $("kpis").innerHTML =
    kpi(entries.length, entries.length === 1 ? "Übung" : "Übungen") +
    kpi(entries.length ? Math.round((doneN / entries.length) * 100) + " %" : "–", "geschafft") +
    kpi(reps, "Wiederholungen*") +
    kpi(period === "day" ? streak() : days, period === "day" ? "Tage Serie" : "aktive Tage") +
    `<p class="small" style="grid-column:1/-1">* Halteübungen zählen 1 Wiederholung pro ${SECONDS_PER_REP} Sekunden, Übungen pro Seite doppelt.</p>`;

  renderBody(muscleLoad(entries));
  renderChart(entries);

  const counts = Object.keys(CATEGORIES).map((k) => [k, entries.filter((l) => l.cat === k).length]);
  const cmax = Math.max(1, ...counts.map((c) => c[1]));
  $("catBars").innerHTML = counts.map(([k, n]) =>
    `<div class="catRow" style="--c:var(--${k})"><span>${CATEGORIES[k].label}</span><div class="bar"><i style="width:${(n / cmax) * 100}%"></i></div><span>${n}</span></div>`).join("");

  $("progress").innerHTML = pool().map((ex) => {
    const all = log.filter((l) => l.ex === ex.id);
    const u = ex.unit === "sec" ? " s" : "";
    const rate = all.length ? Math.round((all.filter((l) => l.done).length / all.length) * 100) + " % geschafft" : "noch nicht gemacht";
    return `<li style="--c:var(--${ex.cat})"><span class="dot"></span><span>${ex.name}<span class="sub">${all.length}× · ${rate}</span></span>` +
      `<span class="num">${ex.base}${u} → <b style="color:var(--fg)">${targetFor(ex)}${u}</b></span></li>`;
  }).join("");

  const recent = entries.slice(-50).reverse();
  $("log").innerHTML = recent.length ? recent.map((l) => {
    const ex = byId[l.ex]; if (!ex) return "";
    const u = ex.unit === "sec" ? " s" : "";
    return `<li style="--c:var(--${l.cat})"><span class="dot"></span><span>${ex.name}<span class="sub">${fmtTime(l.ts)}</span></span>` +
      `<span class="num ${l.done ? "full" : ""}">${l.done ? "✓ " + l.target + u : l.actual + " / " + l.target + u}</span></li>`;
  }).join("") : `<li class="empty" style="display:block">Noch keine Übungen in diesem Zeitraum.</li>`;
}

/* ---------------- Backup ---------------- */
function b64enc(str) { return btoa(unescape(encodeURIComponent(str))); }
function b64dec(b) { return decodeURIComponent(escape(atob(b.replace(/\s/g, "")))); }

function merge(remote) {
  const del = new Set([...deleted, ...(remote.deleted || [])]);
  deleted = [...del];
  const map = new Map();
  [...log, ...(remote.entries || [])].forEach((l) => { if (l && l.id && !del.has(l.id)) map.set(l.id, l); });
  log = [...map.values()].sort((a, b) => a.ts - b.ts);
  persistLog(); save(KEY.deleted, deleted);
}
async function gh(method, body) {
  const url = `https://api.github.com/repos/${backupCfg.repo}/contents/backup.json`;
  const res = await fetch(url, {
    method, cache: "no-store",
    headers: { Authorization: `Bearer ${backupCfg.token}`, Accept: "application/vnd.github+json", "X-GitHub-Api-Version": "2022-11-28" },
    body: body ? JSON.stringify(body) : undefined,
  });
  return res;
}
function ghError(res) {
  if (res.status === 401) return "Token ungültig oder abgelaufen. Leg in GitHub einen neuen an.";
  if (res.status === 403) return "Der Token darf das Repo nicht beschreiben. Prüfe die Berechtigung „Contents: Read and write“.";
  if (res.status === 404) return "Repo nicht gefunden. Prüfe den Namen und ob der Token Zugriff auf genau dieses Repo hat.";
  return `GitHub hat mit Fehler ${res.status} geantwortet. Versuch es später nochmal.`;
}
async function fetchRemote() {
  const res = await gh("GET");
  if (res.status === 404) {
    // Datei existiert noch nicht: Repo-Zugriff trotzdem prüfen
    const r2 = await fetch(`https://api.github.com/repos/${backupCfg.repo}`, { headers: { Authorization: `Bearer ${backupCfg.token}` } });
    if (!r2.ok) throw new Error(ghError(r2));
    return { sha: null, data: null };
  }
  if (!res.ok) throw new Error(ghError(res));
  const j = await res.json();
  return { sha: j.sha, data: JSON.parse(b64dec(j.content)) };
}
async function backupNow() {
  if (!backupCfg.token || !backupCfg.repo) throw new Error("Trag zuerst Repo und Token ein.");
  const remote = await fetchRemote();
  if (remote.data) merge(remote.data);
  const payload = { version: 1, exported: new Date().toISOString(), entries: log, deleted };
  const body = { message: `Backup ${new Date().toLocaleDateString("de-DE")}: ${log.length} Einträge`, content: b64enc(JSON.stringify(payload, null, 1)) };
  if (remote.sha) body.sha = remote.sha;
  const res = await gh("PUT", body);
  if (!res.ok) throw new Error(ghError(res));
  backupCfg.last = Date.now(); save(KEY.backup, backupCfg);
}
async function maybeAutoBackup() {
  if (!backupCfg.token || !navigator.onLine) return;
  if (Date.now() - (backupCfg.last || 0) < 20 * 36e5) return;
  try { await backupNow(); } catch (e) { /* still: nächster Versuch beim nächsten Mal */ }
}

function backupStatusText() {
  if (!backupCfg.token) return "Noch kein Backup eingerichtet.";
  return backupCfg.last ? `Letztes Backup: ${fmtTime(backupCfg.last)}` : "Eingerichtet, aber noch kein Backup gemacht.";
}
$("bkSave").onclick = async () => {
  backupCfg.repo = $("bkRepo").value.trim().replace(/^https:\/\/github\.com\//, "").replace(/\/$/, "");
  const t = $("bkToken").value.trim();
  if (t) backupCfg.token = t;
  save(KEY.backup, backupCfg);
  $("bkStatus").textContent = "Sichere …";
  try { await backupNow(); $("bkStatus").textContent = `Gesichert. ${log.length} Einträge im Repo.`; $("bkToken").value = ""; $("bkToken").placeholder = "gespeichert"; }
  catch (e) { $("bkStatus").textContent = e.message; }
};
$("bkRestore").onclick = async () => {
  $("bkStatus").textContent = "Lade Backup …";
  try {
    if (!backupCfg.token) throw new Error("Trag zuerst Repo und Token ein und tippe auf „Speichern & sichern“.");
    const before = log.length;
    const r = await fetchRemote();
    if (!r.data) throw new Error("Im Repo liegt noch kein Backup.");
    merge(r.data);
    $("bkStatus").textContent = `Backup geladen. ${log.length - before} neue Einträge übernommen.`;
  } catch (e) { $("bkStatus").textContent = e.message; }
};

/* ---------------- Einstellungen ---------------- */
function renderSettings() {
  $("bkRepo").value = backupCfg.repo || "";
  $("bkToken").value = "";
  $("bkToken").placeholder = backupCfg.token ? "gespeichert" : "github_pat_…";
  $("bkStatus").textContent = backupStatusText();
  const equip = [...new Set(EXERCISES.map((e) => e.equipment).filter(Boolean))];
  $("equipPanel").hidden = !equip.length;
  $("equipList").innerHTML = equip.map((q) => `<label class="toggle">${q[0].toUpperCase() + q.slice(1)}<input type="checkbox" id="eq-${q}" data-q="${q}" ${equipOn[q] ? "checked" : ""}></label>`).join("");
  $("equipList").querySelectorAll("input").forEach((i) => i.onchange = () => { equipOn[i.dataset.q] = i.checked; save(KEY.equip, equipOn); });
  $("dataInfo").textContent = `${log.length} Einträge auf diesem Gerät.`;
  $("undoConfirm").hidden = true;
  $("undoBtn").disabled = !log.length;
}
$("undoBtn").onclick = () => {
  const l = log[log.length - 1]; if (!l) return;
  $("undoText").textContent = `${byId[l.ex] ? byId[l.ex].name : l.ex} vom ${fmtTime(l.ts)} löschen?`;
  $("undoConfirm").hidden = false;
};
$("undoNo").onclick = () => ($("undoConfirm").hidden = true);
$("undoYes").onclick = () => {
  const l = log.pop(); if (l) { deleted.push(l.id); save(KEY.deleted, deleted); persistLog(); backupCfg.last = 0; save(KEY.backup, backupCfg); }
  renderSettings();
};

/* ---------------- Start ---------------- */
show("home");
maybeAutoBackup();
if ("serviceWorker" in navigator) navigator.serviceWorker.register("sw.js").catch(() => {});
