// git push-up: eine zufällige Übung pro Wartepause.
"use strict";

const $ = (id) => document.getElementById(id);
const byId = Object.fromEntries(EXERCISES.map((e) => [e.id, e]));

/* ---------------- Speicher ---------------- */
const KEY = { log: "gpu-log", deleted: "gpu-deleted", last: "gpu-lastcat", backup: "gpu-backup", equip: "gpu-equip", period: "gpu-period" };
function load(k, fallback) { try { const v = localStorage.getItem(k); return v ? JSON.parse(v) : fallback; } catch (e) { return fallback; } }
function save(k, v) { try { localStorage.setItem(k, JSON.stringify(v)); } catch (e) {} }

let log = load(KEY.log, []);
let deleted = load(KEY.deleted, []);
let lastCat = load(KEY.last, null);
let backupCfg = load(KEY.backup, { repo: "janerykkh/git-push-up-private", token: "", last: 0 });
let equipOn = load(KEY.equip, {});
let period = load(KEY.period, "day");

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
const SCREENS = ["home", "exercise", "done", "settings"];
function show(name) {
  SCREENS.forEach((s) => ($(s).hidden = s !== name));
  window.scrollTo(0, 0);
  if (name === "home") renderHome();
  if (name === "settings") renderSettings();
}

/* ---------------- Zeit ---------------- */
const MONTHS = ["JAN","FEB","MÄR","APR","MAI","JUN","JUL","AUG","SEP","OKT","NOV","DEZ"];
const WD = ["MO","DI","MI","DO","FR","SA","SO"];
function startOfDay(t = Date.now()) { const d = new Date(t); d.setHours(0, 0, 0, 0); return d.getTime(); }
function streak() {
  const days = new Set(log.map((l) => startOfDay(l.ts)));
  let d = startOfDay();
  if (!days.has(d)) d = startOfDay(d - 12 * 36e5);
  let n = 0;
  while (days.has(d)) { n++; d = startOfDay(d - 12 * 36e5); }
  return n;
}
function periodStart(p) {
  const s = new Date(); s.setHours(0, 0, 0, 0);
  if (p === "week") s.setDate(s.getDate() - ((s.getDay() + 6) % 7));
  if (p === "month") s.setDate(1);
  if (p === "year") s.setMonth(0, 1);
  return s.getTime();
}
const PERIOD_LABEL = { day: "HEUTE", week: "DIESE WOCHE", month: "DIESER MONAT", year: "DIESES JAHR" };

/* ---------------- Startseite ---------------- */
function renderHome() {
  const todayN = log.filter((l) => l.ts >= startOfDay()).length;
  const s = streak();
  const today = log.filter((l) => l.ts >= startOfDay());
  const rate = today.length ? Math.round((today.filter((l) => l.done).length / today.length) * 100) : null;
  $("quick").innerHTML =
    `<div class="q ${s > 0 ? "hot" : ""}"><span>SERIE</span><b>${s}<small>${s === 1 ? "TAG" : "TAGE"}</small></b></div>` +
    `<div class="q ${todayN > 0 ? "ok" : ""}"><span>HEUTE</span><b>${todayN}<small>ÜB.</small></b></div>` +
    `<div class="q"><span>GESCHAFFT</span><b>${rate === null ? "–" : rate}<small>${rate === null ? "" : "%"}</small></b></div>`;
  $("sysline").textContent = !log.length ? "BEREIT FÜR DEN ERSTEN BUILD" : todayN ? "SYSTEME ONLINE" : "HEUTE NOCH OFFLINE";
  $("periodSeg").querySelectorAll("button").forEach((x) => x.setAttribute("aria-selected", x.dataset.p === period ? "true" : "false"));
  renderStats();
}

$("periodSeg").addEventListener("click", (e) => {
  const b = e.target.closest("button[data-p]"); if (!b) return;
  period = b.dataset.p; save(KEY.period, period);
  $("periodSeg").querySelectorAll("button").forEach((x) => x.setAttribute("aria-selected", x === b ? "true" : "false"));
  renderStats();
});

function muscleLoad(entries) {
  const load = Object.fromEntries(Object.keys(MUSCLES).map((m) => [m, 0]));
  entries.forEach((l) => {
    const ex = byId[l.ex]; if (!ex) return;
    const u = unitsOf(l);
    Object.entries(ex.muscles).forEach(([m, w]) => { if (m in load) load[m] += u * w; });
  });
  return load;
}

const MUSCLE_GROUPS = [
  ["OBERKÖRPER", ["chest", "frontDelt", "rearDelt", "upperBack", "lats", "biceps", "triceps"]],
  ["RUMPF", ["abs", "obliques", "lowerBack"]],
  ["BEINE", ["glutes", "quads", "hamstrings", "calves"]],
];
function status(r) {
  if (r >= 0.66) return ["STARK", "s3"];
  if (r >= 0.33) return ["AKTIV", "s2"];
  if (r > 0) return ["SCHWACH", "s1"];
  return ["OFFLINE", "s0"];
}

function renderStats() {
  const s = periodStart(period);
  const entries = log.filter((l) => l.ts >= s);
  const doneN = entries.filter((l) => l.done).length;
  const days = new Set(entries.map((l) => startOfDay(l.ts))).size;
  const reps = Math.round(entries.reduce((a, l) => a + unitsOf(l), 0));

  // Körpermodell
  const load = muscleLoad(entries);
  const max = Math.max(...Object.values(load));
  const ratio = Object.fromEntries(Object.entries(load).map(([m, v]) => [m, max > 0 ? v / max : 0]));
  Body3D.setLoad(ratio);
  const active = Object.values(ratio).filter((r) => r >= 0.33).length;
  $("hudR").textContent = `${active}/${Object.keys(MUSCLES).length} AKTIV`;
  $("hudL").textContent = `BODY SCAN · ${PERIOD_LABEL[period]}`;

  // Kennzahlen
  const kpi = (v, l) => `<div class="kpi"><b>${v}</b>${l}</div>`;
  $("kpis").innerHTML =
    kpi(entries.length, "ÜBUNGEN") +
    kpi(entries.length ? Math.round((doneN / entries.length) * 100) + "%" : "–", "GESCHAFFT") +
    kpi(reps, "WIEDERHOLUNGEN*") +
    kpi(days, days === 1 ? "AKTIVER TAG" : "AKTIVE TAGE");

  // Muskelgruppen-Liste im Hangar-Stil
  $("muscles").innerHTML = MUSCLE_GROUPS.map(([g, ms]) => {
    const on = ms.filter((m) => ratio[m] >= 0.33).length;
    const dots = ms.map((m) => (ratio[m] >= 0.33 ? "●" : "○")).join("");
    return `<div class="mgroup"><h3>${g} <span style="color:var(--wire)">${dots}</span></h3>` +
      ms.map((m) => {
        const [label, cls] = status(ratio[m]);
        return `<div class="mrow"><span class="nm">${MUSCLES[m]}</span><span class="st ${cls}">${label}</span>` +
          `<span class="meter st ${cls}"><i style="width:${Math.round(ratio[m] * 100)}%"></i></span></div>`;
      }).join("") + `</div>`;
  }).join("");

  renderChart(entries, s);

  const counts = Object.keys(CATEGORIES).map((k) => [k, entries.filter((l) => l.cat === k).length]);
  const cmax = Math.max(1, ...counts.map((c) => c[1]));
  $("catBars").innerHTML = counts.map(([k, n]) =>
    `<div class="catRow" style="--c:var(--${k})"><span>${CATEGORIES[k].label.toUpperCase()}</span><div class="bar"><i style="width:${(n / cmax) * 100}%"></i></div><span>${n}</span></div>`).join("");

  $("progress").innerHTML = pool().map((ex) => {
    const all = log.filter((l) => l.ex === ex.id);
    const u = ex.unit === "sec" ? " s" : "";
    const rate = all.length ? Math.round((all.filter((l) => l.done).length / all.length) * 100) + "% geschafft" : "noch nicht gemacht";
    return `<li style="--c:var(--${ex.cat})"><span class="dot"></span><span>${ex.name}<span class="sub">${all.length}× · ${rate}</span></span>` +
      `<span class="num">${ex.base}${u} → <b>${targetFor(ex)}${u}</b></span></li>`;
  }).join("");

  const recent = entries.slice(-40).reverse();
  $("log").innerHTML = recent.length ? recent.map((l) => {
    const ex = byId[l.ex]; if (!ex) return "";
    const u = ex.unit === "sec" ? " s" : "";
    return `<li style="--c:var(--${l.cat})"><span class="dot"></span><span>${ex.name}<span class="sub">${fmtTime(l.ts)}</span></span>` +
      `<span class="num ${l.done ? "full" : ""}">${l.done ? "✓ " + l.target + u : l.actual + " / " + l.target + u}</span></li>`;
  }).join("") : `<li class="empty" style="display:block">Noch keine Übungen ${period === "day" ? "heute" : "in diesem Zeitraum"}.</li>`;
}

function renderChart(entries, s) {
  let buckets, labels, every, title;
  if (period === "day") {
    buckets = new Array(24).fill(0); labels = buckets.map((_, i) => `${i}`); every = 6; title = "AKTIVITÄT NACH UHRZEIT";
    entries.forEach((l) => buckets[new Date(l.ts).getHours()]++);
  } else if (period === "week") {
    buckets = new Array(7).fill(0); labels = WD; every = 1; title = "ÜBUNGEN PRO TAG";
    entries.forEach((l) => { const i = Math.floor((startOfDay(l.ts) - s) / 864e5 + 0.5); if (i >= 0 && i < 7) buckets[i]++; });
  } else if (period === "month") {
    const d = new Date(s); const n = new Date(d.getFullYear(), d.getMonth() + 1, 0).getDate();
    buckets = new Array(n).fill(0); labels = buckets.map((_, i) => `${i + 1}`); every = 7; title = "ÜBUNGEN PRO TAG";
    entries.forEach((l) => buckets[new Date(l.ts).getDate() - 1]++);
  } else {
    buckets = new Array(12).fill(0); labels = MONTHS; every = 2; title = "ÜBUNGEN PRO MONAT";
    entries.forEach((l) => buckets[new Date(l.ts).getMonth()]++);
  }
  $("chartTitle").textContent = title;
  const W = 320, H = 110, top = 12;
  const max = Math.max(1, ...buckets);
  const bw = (W - 8) / buckets.length;
  let svg = `<svg viewBox="0 0 ${W} ${H + 16}" role="img" aria-label="${title}"><defs><filter id="gl"><feGaussianBlur stdDeviation="1.6"/><feMerge><feMergeNode/><feMergeNode in="SourceGraphic"/></feMerge></filter></defs>`;
  for (let g = 0; g <= 4; g++) { const y = top + ((H - top) * g) / 4; svg += `<line x1="0" y1="${y}" x2="${W}" y2="${y}" stroke="#14222a" stroke-width="1"/>`; }
  svg += `<text x="${W}" y="${top - 3}" text-anchor="end">${max}</text>`;
  buckets.forEach((v, i) => {
    const h = (v / max) * (H - top);
    const x = 4 + i * bw + bw * 0.18;
    svg += `<rect x="${x}" y="${H - 1.5}" width="${bw * 0.64}" height="1.5" fill="#1d3038"/>`;
    if (v) svg += `<rect x="${x}" y="${H - h}" width="${bw * 0.64}" height="${h}" fill="#7ef0a6" fill-opacity="0.85" filter="url(#gl)"/>`;
    if (i % every === 0) svg += `<text x="${4 + i * bw + bw / 2}" y="${H + 13}" text-anchor="middle">${labels[i]}</text>`;
  });
  $("chart").innerHTML = svg + "</svg>";
}

function fmtTime(ts) {
  const d = new Date(ts);
  return d.toLocaleDateString("de-DE", { day: "2-digit", month: "2-digit" }) + " · " + d.toLocaleTimeString("de-DE", { hour: "2-digit", minute: "2-digit" });
}

/* ---------------- Übung ---------------- */
let current = null, timer = null, anim = 0;
function pool() { return EXERCISES.filter((e) => !e.equipment || equipOn[e.equipment]); }
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
  $("exercise").style.setProperty("--c", `var(--${ex.cat})`);
  $("exCat").textContent = CATEGORIES[ex.cat].label.toUpperCase();
  $("exName").textContent = ex.name;
  $("exTarget").textContent = current.target;
  $("exUnit").textContent = (ex.unit === "sec" ? "SEKUNDEN HALTEN" : "WIEDERHOLUNGEN") + (ex.side ? " PRO SEITE" : "");
  $("exCue").textContent = ex.cue;
  $("exNote").hidden = !ex.note; $("exNote").textContent = ex.note || "";
  $("timerRow").hidden = ex.unit !== "sec"; $("timerVal").textContent = "0 s"; $("timerBtn").textContent = "TIMER STARTEN";
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
$("toSettings").onclick = () => show("settings");
$("settingsBack").onclick = () => show("home");

function finish(done, actual) {
  stopTimer();
  const { ex, target } = current;
  log.push({ id: uid(), ex: ex.id, cat: ex.cat, target, actual, done, ts: Date.now() });
  persistLog();
  lastCat = ex.cat; save(KEY.last, lastCat);
  const u = ex.unit === "sec" ? " s" : "";
  const side = ex.side ? " pro Seite" : "";
  $("doneIcon").className = done ? "stamp" : "stamp partly";
  $("doneIcon").textContent = done ? "INSTALLED" : "LOGGED";
  $("doneText").textContent = done ? `${target}${u} ${ex.name}${side}` : `${actual} von ${target}${u} ${ex.name}`;
  show("done");
  setTimeout(() => { if (!$("done").hidden) show("home"); }, 1500);
  maybeAutoBackup();
}
$("done").onclick = () => show("home");

function stopTimer() { if (timer) { clearInterval(timer); timer = null; } }
$("timerBtn").onclick = () => {
  if (timer) { stopTimer(); $("timerBtn").textContent = "TIMER STARTEN"; return; }
  const t0 = Date.now();
  $("timerBtn").textContent = "STOPP";
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
  const lines = LIMBS.map(() => `<line stroke-width="4" stroke-linecap="round"/>`).join("");
  let grid = "";
  for (let x = 10; x <= 230; x += 20) grid += `<line x1="${x}" y1="152" x2="${120 + (x - 120) * 1.6}" y2="165" stroke="#14222a"/>`;
  $("figure").innerHTML = `<svg viewBox="0 0 240 165" role="img" aria-label="Animation: ${ex.name}">
    <defs><filter id="fg" x="-20%" y="-20%" width="140%" height="140%"><feGaussianBlur stdDeviation="2.2"/><feMerge><feMergeNode/><feMergeNode in="SourceGraphic"/></feMerge></filter></defs>
    ${grid}<line x1="6" y1="152" x2="234" y2="152" stroke="#1d3038" stroke-width="1"/>
    <g stroke="var(--${ex.cat})" fill="none" filter="url(#fg)">${lines}<circle r="9" stroke-width="3" fill="#04070a"/></g></svg>`;
  const svg = $("figure").querySelector("svg");
  const ls = svg.querySelectorAll("g line"), head = svg.querySelector("circle");
  const reduce = matchMedia("(prefers-reduced-motion: reduce)").matches;
  const per = ex.unit === "sec" ? 4200 : 2400;
  const t0 = performance.now();
  function frame(now) {
    if (!svg.isConnected) return;
    const ph = ((now - t0) % per) / per;
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
    head.setAttribute("cx", n[0] + (dx / d) * 11); head.setAttribute("cy", n[1] + (dy / d) * 11);
    if (!reduce) anim = requestAnimationFrame(frame);
  }
  anim = requestAnimationFrame(frame);
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
  $("equipList").innerHTML = equip.map((q) => `<label class="toggle">${q}<input type="checkbox" id="eq-${q}" data-q="${q}" ${equipOn[q] ? "checked" : ""}></label>`).join("");
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
Body3D.init($("bodyCanvas"), (a) => {
  const deg = ((Math.round((a * 180) / Math.PI) % 360) + 360) % 360;
  $("hudB").textContent = `ROT ${String(deg).padStart(3, "0")}°`;
});
show("home");
maybeAutoBackup();
if ("serviceWorker" in navigator) navigator.serviceWorker.register("sw.js").catch(() => {});
