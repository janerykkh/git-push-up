// git push-up: eine Übung pro Wartepause, ausgewählt von einem kleinen Trainer.
"use strict";

const $ = (id) => document.getElementById(id);
const byId = Object.fromEntries(EXERCISES.map((e) => [e.id, e]));
const HOUR = 36e5, DAY = 864e5;

/* ---------------- Speicher ---------------- */
const KEY = { log: "gpu-log", deleted: "gpu-deleted", last: "gpu-lastcat", backup: "gpu-backup", equip: "gpu-equip",
  period: "gpu-period", trainer: "gpu-trainer" };
function load(k, fallback) { try { const v = localStorage.getItem(k); return v ? JSON.parse(v) : fallback; } catch (e) { return fallback; } }
function save(k, v) { try { localStorage.setItem(k, JSON.stringify(v)); } catch (e) {} }

let log = load(KEY.log, []);
let deleted = load(KEY.deleted, []);
let lastCat = load(KEY.last, null);
let backupCfg = load(KEY.backup, { repo: "janerykkh/git-push-up-private", token: "", last: 0 });
let equipOn = load(KEY.equip, {});
let period = load(KEY.period, "day");
let trainer = load(KEY.trainer, { baseline: null, baselineDate: 0, pending: {}, targets: {}, updated: 0 });
let selMuscle = null;

if (navigator.storage && navigator.storage.persist) navigator.storage.persist().catch(() => {});
function persistLog() { save(KEY.log, log); }
function saveTrainer() { trainer.updated = Date.now(); save(KEY.trainer, trainer); }
function uid() { return Date.now().toString(36) + Math.random().toString(36).slice(2, 8); }

/* ---------------- Trainer: Maximum, Ziele, Wochenanpassung ---------------- */
function markerValue(id) {
  const m = MARKERS.find((x) => x.id === id);
  return (trainer.baseline && trainer.baseline[id]) || (m ? m.fallback : 10);
}
function estMax(ex) {
  if (!ex.marker) return ex.base / WORK_FRACTION;
  return Math.max(1, markerValue(ex.marker) * (ex.factor || 1));
}
function roundTarget(ex, v) {
  return ex.unit === "sec" ? Math.max(10, Math.round(v / 5) * 5) : Math.max(1, Math.round(v));
}
function targetFor(ex) {
  const st = trainer.targets[ex.id];
  return st ? st.t : roundTarget(ex, estMax(ex) * WORK_FRACTION);
}
function weeklyReview() {
  const now = Date.now();
  let changed = false;
  pool().forEach((ex) => {
    let st = trainer.targets[ex.id];
    if (!st) { trainer.targets[ex.id] = { t: targetFor(ex), reviewed: now, change: 0 }; changed = true; return; }
    if (now - st.reviewed < 7 * DAY) return;
    const recent = log.filter((l) => l.ex === ex.id && !l.test && l.ts >= st.reviewed);
    const succ = recent.filter((l) => l.done).length, fail = recent.length - succ;
    const old = st.t;
    if (recent.length >= 2 && succ / recent.length >= 0.8) {
      const cap = roundTarget(ex, estMax(ex) * 0.85);
      const step = ex.unit === "sec" ? 5 : 1;
      st.t = Math.min(cap, roundTarget(ex, Math.max(st.t * 1.1, st.t + step)));
      if (st.t < old) st.t = old;
    } else if (fail >= 2) {
      st.t = roundTarget(ex, st.t * 0.9);
    }
    st.change = st.t - old;
    st.reviewed = now;
    changed = true;
  });
  if (changed) saveTrainer();
}
function nextReviewDays() {
  const ts = Object.values(trainer.targets).map((t) => t.reviewed);
  if (!ts.length) return 7;
  return Math.max(0, Math.ceil((Math.min(...ts) + 7 * DAY - Date.now()) / DAY));
}
function recordDue() { return !trainer.baselineDate || Date.now() - trainer.baselineDate >= RECORD_EVERY_DAYS * DAY; }
function daysToRecord() { return Math.max(0, Math.ceil((trainer.baselineDate + RECORD_EVERY_DAYS * DAY - Date.now()) / DAY)); }

/* ---------------- Erschöpfung ---------------- */
// Jeder Satz erschöpft einen Muskel relativ zu deinem Maximum; danach klingt das exponentiell ab
// (nach RECOVERY_HOURS sind noch 10 % übrig).
function fatigueAt(t = Date.now()) {
  const F = Object.fromEntries(Object.keys(MUSCLES).map((m) => [m, 0]));
  for (let i = log.length - 1; i >= 0; i--) {
    const l = log[i];
    if (t - l.ts > 7 * DAY) break;
    if (l.ts > t) continue;
    const ex = byId[l.ex]; if (!ex) continue;
    const rel = l.actual / estMax(ex);
    const h = (t - l.ts) / HOUR;
    for (const [m, w] of Object.entries(ex.muscles)) {
      if (!(m in F)) continue;
      F[m] += (w * rel / FULL_EFFORT) * Math.pow(10, -h / RECOVERY_HOURS[m]);
    }
  }
  return F;
}
function hoursToRecover(m, f) { return f <= 0.1 ? 0 : Math.ceil(RECOVERY_HOURS[m] * Math.log10(f / 0.1)); }
function pctText(f) { return Math.round(Math.min(1, f) * 100) + "%"; }

/* ---------------- Übungsauswahl ---------------- */
function pool() { return EXERCISES.filter((e) => !e.retired && (!e.equipment || equipOn[e.equipment])); }
// Passt ein Ziel nicht in etwa eine Minute (cap), wird es pro Mal auf einen Satz verkleinert; der Rest kommt bei späteren Malen
function setsFor(ex, target) {
  const n = ex.cap && target > ex.cap ? Math.ceil(target / ex.cap) : 1;
  let per = Math.ceil(target / n);
  if (ex.unit === "sec") per = Math.ceil(per / 5) * 5;
  return { n, per };
}

// Wie gut passt eine Übung gerade? Hoch = trifft frische Muskeln, niedrig = Hauptmuskel noch erschöpft.
function score(ex, F) {
  let sum = 0, wsum = 0, pen = 0;
  for (const [m, w] of Object.entries(ex.muscles)) {
    const f = Math.min(1, F[m] || 0);
    sum += w * (1 - f); wsum += w;
    if (w >= 1 && f >= 0.8) pen += 0.6;
  }
  let s = sum / wsum - pen;
  if (ex.cat === lastCat) s -= 0.1;
  // Lange nicht gemacht: Bonus wächst über zwei Tage; gerade erst gemacht: Abzug
  const h = hoursSince(ex.id);
  s += 0.25 * Math.min(1, h / 48);
  if (h < 1) s -= 0.5;
  return s;
}
function hoursSince(id) {
  for (let i = log.length - 1; i >= 0; i--) if (log[i].ex === id && !log[i].test) return (Date.now() - log[i].ts) / HOUR;
  return 96;
}
let lastEx = load("gpu-lastex", null);
function trainerPick(excludeId) {
  const F = fatigueAt();
  if (!excludeId) excludeId = lastEx;
  const rank = (list) => list.filter((e) => e.id !== excludeId).map((e) => ({ e, s: score(e, F) })).sort((a, b) => b.s - a.s);
  let r = rank(pool());
  if (!r.length) r = pool().map((e) => ({ e, s: 0 }));
  const top = r.filter((x) => x.s >= r[0].s - 0.08);
  return top[Math.floor(Math.random() * top.length)].e;
}
function whyText(ex) {
  const F = fatigueAt();
  const main = Object.entries(ex.muscles).filter(([, w]) => w >= 1).map(([m]) => m);
  const fresh = main.filter((m) => F[m] < 0.3).map((m) => MUSCLES[m]);
  const tired = main.filter((m) => F[m] >= 0.8).map((m) => MUSCLES[m]);
  if (tired.length) return `TRAINER: ${tired.join(", ")} noch erschöpft, mach es locker.`;
  if (fresh.length) return `TRAINER: ${fresh.join(" + ")} ${fresh.length > 1 ? "sind" : "ist"} frisch.`;
  return "TRAINER: gute Verteilung für jetzt.";
}
function bestFor(m) {
  const cands = pool().filter((e) => e.muscles[m]);
  if (!cands.length) return null;
  const top = Math.max(...cands.map((e) => e.muscles[m]));
  const best = cands.filter((e) => e.muscles[m] === top);
  best.sort((x, y) => hoursSince(y.id) - hoursSince(x.id));
  return best[0];
}

/* ---------------- Bildschirme ---------------- */
const SCREENS = ["home", "exercise", "done", "settings", "record"];
function show(name) {
  SCREENS.forEach((s) => ($(s).hidden = s !== name));
  window.scrollTo(0, 0);
  if (name === "home") { weeklyReview(); renderHome(); }
  if (name === "settings") renderSettings();
  if (name === "record") renderRecord();
}

/* ---------------- Zeit ---------------- */
const MONTHS = ["JAN","FEB","MÄR","APR","MAI","JUN","JUL","AUG","SEP","OKT","NOV","DEZ"];
const WD = ["MO","DI","MI","DO","FR","SA","SO"];
function startOfDay(t = Date.now()) { const d = new Date(t); d.setHours(0, 0, 0, 0); return d.getTime(); }
function streak() {
  const days = new Set(log.map((l) => startOfDay(l.ts)));
  let d = startOfDay();
  if (!days.has(d)) d = startOfDay(d - 12 * HOUR);
  let n = 0;
  while (days.has(d)) { n++; d = startOfDay(d - 12 * HOUR); }
  return n;
}
function periodStart(p) {
  const s = new Date(); s.setHours(0, 0, 0, 0);
  if (p === "week") s.setDate(s.getDate() - ((s.getDay() + 6) % 7));
  if (p === "month") s.setDate(1);
  if (p === "year") s.setMonth(0, 1);
  return s.getTime();
}
function fmtTime(ts) {
  const d = new Date(ts);
  return d.toLocaleDateString("de-DE", { day: "2-digit", month: "2-digit" }) + " · " + d.toLocaleTimeString("de-DE", { hour: "2-digit", minute: "2-digit" });
}

/* ---------------- Startseite ---------------- */
const MUSCLE_GROUPS = [
  ["OBERKÖRPER", ["chest", "frontDelt", "rearDelt", "upperBack", "lats", "biceps", "triceps"]],
  ["RUMPF", ["abs", "obliques", "lowerBack"]],
  ["BEINE", ["glutes", "quads", "hamstrings", "calves"]],
];
let lastF = {};

function renderHome() {
  const today = log.filter((l) => l.ts >= startOfDay());
  const s = streak();
  const rate = today.length ? Math.round((today.filter((l) => l.done).length / today.length) * 100) : null;
  $("quick").innerHTML =
    `<div class="q ${s > 0 ? "hot" : ""}"><span>SERIE</span><b>${s}<small>${s === 1 ? "TAG" : "TAGE"}</small></b></div>` +
    `<div class="q ${today.length ? "ok" : ""}"><span>HEUTE</span><b>${today.length}<small>ÜB.</small></b></div>` +
    `<div class="q"><span>GESCHAFFT</span><b>${rate === null ? "–" : rate}<small>${rate === null ? "" : "%"}</small></b></div>`;

  const first = !trainer.baselineDate;
  $("goBtn").classList.toggle("rec", first);
  $("goLabel").textContent = first ? "REKORDTAG" : "ÜBUNG";
  $("roundInfo").textContent = first ? "EINMAL DEINE BASELINE MESSEN" : "";
  $("roundInfo").hidden = !first;
  $("recBanner").hidden = first || !recordDue();
  $("recBanner").innerHTML = `REKORDTAG FÄLLIG <span>5 TESTS · ~12 MIN</span>`;
  $("sysline").textContent = first ? "KALIBRIERUNG NÖTIG" : today.length ? "SYSTEME ONLINE" : "BEREIT";
  $("periodSeg").querySelectorAll("button").forEach((x) => x.setAttribute("aria-selected", x.dataset.p === period ? "true" : "false"));
  renderFatigue();
  renderStats();
}

function renderFatigue() {
  const F = fatigueAt();
  lastF = F;
  Body3D.setLoad(F);
  const tired = Object.values(F).filter((f) => f >= 0.5).length;
  $("hudR").textContent = `${tired}/${Object.keys(MUSCLES).length} AUSGELASTET`;
  $("muscles").innerHTML = MUSCLE_GROUPS.map(([g, ms]) => {
    const avg = ms.reduce((a, m) => a + Math.min(1, F[m]), 0) / ms.length;
    return `<div class="mgroup"><h3>${g}<b>${pctText(avg)}</b></h3>` +
      ms.map((m) => {
        const f = F[m], c = f >= 0.8 ? "p2" : f > 0.05 ? "p1" : "";
        const h = hoursToRecover(m, f);
        return `<div class="mrow ${selMuscle === m ? "sel" : ""}" data-m="${m}"><span class="nm">${MUSCLES[m]}</span><span class="pct ${c}">${pctText(f)}</span>` +
          `<span class="meter"><i class="${c}" style="width:${Math.min(100, Math.round(f * 100))}%"></i></span>` +
          (h ? `<span class="rec">erholt in ca. ${h} h</span>` : "") + `</div>`;
      }).join("") + `</div>`;
  }).join("");
  $("muscles").querySelectorAll(".mrow").forEach((el) => el.onclick = () => {
    selectMuscle(selMuscle === el.dataset.m ? null : el.dataset.m);
    if (selMuscle) $("mInfo").scrollIntoView({ behavior: "smooth", block: "center" });
  });
  renderMuscleInfo();
}

function selectMuscle(m) {
  selMuscle = m; Body3D.select(m);
  $("muscles").querySelectorAll(".mrow").forEach((el) => el.classList.toggle("sel", el.dataset.m === m));
  renderMuscleInfo();
}
function renderMuscleInfo() {
  const m = selMuscle;
  $("mInfo").hidden = !m;
  if (!m) return;
  const f = lastF[m] || 0, h = hoursToRecover(m, f);
  $("mInfoName").textContent = MUSCLES[m];
  $("mInfoPct").textContent = pctText(f);
  $("mInfoSub").textContent = h ? `ERSCHÖPFT · ERHOLT IN CA. ${h} H` : "ERHOLT · BEREIT";
  $("mInfoBar").style.width = Math.min(100, Math.round(f * 100)) + "%";
  const hitters = pool().filter((e) => e.muscles[m]).sort((a, b) => b.muscles[m] - a.muscles[m]);
  const w = (x) => (x >= 1 ? "Haupt" : x >= 0.5 ? "Neben" : "hilft mit");
  $("mInfoEx").textContent = (hitters.length
    ? "Trainiert durch: " + hitters.map((e) => `${e.name} (${w(e.muscles[m])})`).join(", ") + ". "
    : "Keine Übung im Pool trifft diesen Muskel. Mit Hanteln kämen z. B. Rudern oder Bizeps-Curls dazu. ") +
    `Volle Erholung dauert etwa ${RECOVERY_HOURS[m]} h.`;
  const ex = bestFor(m);
  $("mInfoGo").hidden = !ex || !trainer.baselineDate;
  if (ex) { $("mInfoGo").textContent = `ÜBUNG: ${ex.name.toUpperCase()}`; $("mInfoGo").onclick = () => startExercise(ex); }
}
$("mInfoClose").onclick = () => selectMuscle(null);

$("periodSeg").addEventListener("click", (e) => {
  const b = e.target.closest("button[data-p]"); if (!b) return;
  period = b.dataset.p; save(KEY.period, period);
  $("periodSeg").querySelectorAll("button").forEach((x) => x.setAttribute("aria-selected", x === b ? "true" : "false"));
  renderStats();
});

function unitsOf(entry) {
  const ex = byId[entry.ex]; if (!ex) return 0;
  let u = ex.unit === "sec" ? entry.actual / SECONDS_PER_REP : entry.actual;
  if (ex.side) u *= 2;
  return u;
}

function renderStats() {
  const s = periodStart(period);
  const entries = log.filter((l) => l.ts >= s);
  const normal = entries.filter((l) => !l.test);
  const doneN = normal.filter((l) => l.done).length;
  const days = new Set(entries.map((l) => startOfDay(l.ts))).size;
  const reps = Math.round(entries.reduce((a, l) => a + unitsOf(l), 0));
  const kpi = (v, l) => `<div class="kpi"><b>${v}</b>${l}</div>`;
  $("kpis").innerHTML =
    kpi(entries.length, "ÜBUNGEN") +
    kpi(normal.length ? Math.round((doneN / normal.length) * 100) + "%" : "–", "GESCHAFFT") +
    kpi(reps, "WIEDERHOLUNGEN*") +
    kpi(days, days === 1 ? "AKTIVER TAG" : "AKTIVE TAGE");

  renderChart(entries, s);

  const counts = Object.keys(CATEGORIES).map((k) => [k, entries.filter((l) => l.cat === k).length]);
  const cmax = Math.max(1, ...counts.map((c) => c[1]));
  $("catBars").innerHTML = counts.map(([k, n]) =>
    `<div class="catRow" style="--c:var(--${k})"><span>${CATEGORIES[k].label.toUpperCase()}</span><div class="bar"><i style="width:${(n / cmax) * 100}%"></i></div><span>${n}</span></div>`).join("");

  const nd = nextReviewDays();
  $("reviewInfo").textContent = trainer.baselineDate
    ? `Anpassung in ${nd} ${nd === 1 ? "Tag" : "Tagen"} · Rekordtag in ${daysToRecord()} T`
    : "Noch keine Baseline";
  $("progress").innerHTML = pool().map((ex) => {
    const all = log.filter((l) => l.ex === ex.id && !l.test);
    const u = ex.unit === "sec" ? " s" : "";
    const st = trainer.targets[ex.id];
    const trend = st && st.change ? (st.change > 0 ? ` <span style="color:var(--phos)">▲${st.change}</span>` : ` <span style="color:var(--amber)">▼${-st.change}</span>`) : "";
    const isMarker = MARKERS.find((m) => m.id === ex.id);
    const pr = isMarker && trainer.baseline && trainer.baseline[ex.id] ? ` · Rekord <span class="pr">${trainer.baseline[ex.id]}${u}</span>` : "";
    const rate = all.length ? Math.round((all.filter((l) => l.done).length / all.length) * 100) + "% geschafft" : "noch nicht gemacht";
    return `<li style="--c:var(--${ex.cat})"><span class="dot"></span><span>${ex.name}<span class="sub">${all.length}× · ${rate}${pr}</span></span>` +
      `<span class="num">${(() => { const s = setsFor(ex, targetFor(ex)); return `${s.n > 1 ? s.n + "× " : ""}<b>${s.per}${u}</b>`; })()}${ex.side ? "/S" : ""}${trend}</span></li>`;
  }).join("");

  const recent = entries.slice(-40).reverse();
  $("log").innerHTML = recent.length ? recent.map((l) => {
    const ex = byId[l.ex]; if (!ex) return "";
    const u = ex.unit === "sec" ? " s" : "";
    const res = l.test ? `<span class="pr">REKORD ${l.actual}${u}</span>` : l.done ? "✓ " + l.target + u : l.actual + " / " + l.target + u;
    return `<li style="--c:var(--${l.cat})"><span class="dot"></span><span>${ex.name}<span class="sub">${fmtTime(l.ts)}</span></span>` +
      `<span class="num ${l.done && !l.test ? "full" : ""}">${res}</span></li>`;
  }).join("") : `<li class="empty" style="display:block">Noch keine Übungen ${period === "day" ? "heute" : "in diesem Zeitraum"}.</li>`;
}

function renderChart(entries, s) {
  let buckets, labels, every, title;
  if (period === "day") {
    buckets = new Array(24).fill(0); labels = buckets.map((_, i) => `${i}`); every = 6; title = "AKTIVITÄT NACH UHRZEIT";
    entries.forEach((l) => buckets[new Date(l.ts).getHours()]++);
  } else if (period === "week") {
    buckets = new Array(7).fill(0); labels = WD; every = 1; title = "ÜBUNGEN PRO TAG";
    entries.forEach((l) => { const i = Math.floor((startOfDay(l.ts) - s) / DAY + 0.5); if (i >= 0 && i < 7) buckets[i]++; });
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

/* ---------------- Übung ---------------- */
let current = null, timer = null;
function startExercise(ex) {
  stopTimer();
  current = { ex, target: setsFor(ex, targetFor(ex)).per };
  $("exercise").style.setProperty("--c", `var(--${ex.cat})`);
  $("exCat").textContent = CATEGORIES[ex.cat].label.toUpperCase();
  $("exName").textContent = ex.name;
  $("exTarget").textContent = current.target;
  $("exUnit").textContent = (ex.unit === "sec" ? "SEKUNDEN HALTEN" : "WIEDERHOLUNGEN") + (ex.side ? " PRO SEITE" : "");
  $("exCue").textContent = ex.cue;
  $("exNote").hidden = !ex.note; $("exNote").textContent = ex.note || "";
  $("exWhy").textContent = whyText(ex);
  $("timerRow").hidden = ex.unit !== "sec"; $("timerVal").textContent = "0 s"; $("timerBtn").textContent = "TIMER STARTEN";
  $("doneRow").hidden = false; $("partialForm").hidden = true; $("skipBtn").hidden = false;
  $("partialLabel").textContent = (ex.unit === "sec" ? "Wie viele Sekunden hast du gehalten?" : "Wie viele Wiederholungen hast du geschafft?");
  $("partialIn").value = "";
  drawFigure(ex, $("figure"));
  show("exercise");
}
$("goBtn").onclick = () => { if (!trainer.baselineDate) { show("record"); return; } startExercise(trainerPick(null)); };
$("recBanner").onclick = () => show("record");
$("skipBtn").onclick = () => startExercise(trainerPick(current.ex.id));
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
  lastEx = ex.id; save("gpu-lastex", lastEx);
  lastCat = ex.cat; save(KEY.last, lastCat);
  const u = ex.unit === "sec" ? " s" : "";
  const side = ex.side ? " pro Seite" : "";
  showDone(done ? "INSTALLED" : "LOGGED", !done, done ? `${target}${u} ${ex.name}${side}` : `${actual} von ${target}${u} ${ex.name}`);
  maybeAutoBackup();
}
function showDone(stamp, partly, text) {
  $("doneIcon").className = partly ? "stamp partly" : "stamp";
  $("doneIcon").textContent = stamp;
  $("doneText").textContent = text;
  show("done");
  setTimeout(() => { if (!$("done").hidden) show("home"); }, 1600);
}
$("done").onclick = () => show("home");

function stopTimer() { if (timer) { clearInterval(timer); timer = null; } }
function runTimer(btn, valEl, inputEl, goal) {
  if (timer) { stopTimer(); btn.textContent = "TIMER STARTEN"; return; }
  const t0 = Date.now();
  btn.textContent = "STOPP";
  timer = setInterval(() => {
    const s = Math.floor((Date.now() - t0) / 1000);
    valEl.textContent = goal && s >= goal ? `${s} s ✓` : `${s} s`;
    inputEl.value = s;
  }, 250);
}
$("timerBtn").onclick = () => runTimer($("timerBtn"), $("timerVal"), $("partialIn"), current.target);

/* ---------------- Rekordtag ---------------- */
let recSel = null;
function renderRecord() {
  stopTimer();
  const first = !trainer.baselineDate;
  $("recIntro").textContent = (first
    ? "Einmalige Kalibrierung: fünf kurze Tests, daraus berechnet der Trainer deine Ziele. "
    : "Alle vier Wochen: neue Rekorde, neue Baseline. ") +
    "Jeweils so viel wie sauber geht, dann aufhören. Zwischen den Tests 2–3 Minuten Pause. Du musst nicht alle auf einmal machen.";
  $("recList").innerHTML = MARKERS.map((m) => {
    const u = m.unit === "sec" ? " s" : "";
    const prev = trainer.baseline && trainer.baseline[m.id];
    const now = trainer.pending[m.id];
    const right = now != null ? `✓ ${now}${u}${prev && now > prev ? ' <span class="pr">NEU!</span>' : ""}` : "offen";
    const ex = byId[m.id];
    return `<li class="${now != null ? "done" : ""} ${recSel === m.id ? "sel" : ""}" data-m="${m.id}" style="--c:var(--${ex.cat})"><span class="dot"></span>` +
      `<span>${m.label}<span class="sub">${prev ? `Bisher: ${prev}${u}` : "noch kein Rekord"}</span></span><span class="num">${right}</span></li>`;
  }).join("");
  $("recList").querySelectorAll("li").forEach((li) => li.onclick = () => openTest(li.dataset.m));
  const n = Object.keys(trainer.pending).length;
  $("recFinish").hidden = n === 0;
  $("recFinish").textContent = n < MARKERS.length ? `MIT ${n}/${MARKERS.length} TESTS ABSCHLIESSEN` : "REKORDTAG ABSCHLIESSEN";
  $("recTest").hidden = !recSel;
  if (!recSel) { const next = MARKERS.find((m) => trainer.pending[m.id] == null); if (next && n === 0) openTest(next.id); }
}
function openTest(id) {
  stopTimer();
  recSel = id;
  const m = MARKERS.find((x) => x.id === id), ex = byId[id];
  $("record").style.setProperty("--c", `var(--${ex.cat})`);
  $("recName").textContent = m.label;
  $("recHow").textContent = m.how;
  $("recTimerRow").hidden = m.unit !== "sec";
  $("recTimerVal").textContent = "0 s"; $("recTimerBtn").textContent = "TIMER STARTEN";
  $("recLabel").textContent = m.unit === "sec" ? "Wie viele Sekunden hast du gehalten?" : "Wie viele hast du geschafft?";
  $("recIn").value = trainer.pending[id] != null ? trainer.pending[id] : "";
  $("recTest").hidden = false;
  drawFigure(ex, $("recFigure"));
  $("recList").querySelectorAll("li").forEach((li) => li.classList.toggle("sel", li.dataset.m === id));
  $("recTest").scrollIntoView({ behavior: "smooth", block: "start" });
}
$("recTimerBtn").onclick = () => runTimer($("recTimerBtn"), $("recTimerVal"), $("recIn"), 0);
$("recForm").addEventListener("submit", (e) => {
  e.preventDefault(); stopTimer();
  const v = Math.max(1, parseInt($("recIn").value, 10) || 0);
  const ex = byId[recSel];
  trainer.pending[recSel] = v; saveTrainer();
  log.push({ id: uid(), ex: ex.id, cat: ex.cat, target: 0, actual: v, done: true, test: true, ts: Date.now() });
  persistLog();
  const next = MARKERS.find((m) => trainer.pending[m.id] == null);
  recSel = null;
  renderRecord();
  if (next) openTest(next.id); else window.scrollTo(0, 0);
});
$("recBack").onclick = () => { stopTimer(); recSel = null; show("home"); };
$("recFinish").onclick = () => {
  trainer.baseline = { ...(trainer.baseline || {}), ...trainer.pending };
  trainer.baselineDate = Date.now();
  trainer.pending = {};
  trainer.targets = {};
  pool().forEach((ex) => { trainer.targets[ex.id] = { t: roundTarget(ex, estMax(ex) * WORK_FRACTION), reviewed: Date.now(), change: 0 }; });
  saveTrainer();
  recSel = null;
  showDone("BASELINE", false, "Ziele neu berechnet. Nächster Rekordtag in 4 Wochen.");
  if (backupCfg.token) backupNow().catch(() => {}); // Baseline sofort sichern, nicht erst nach 20 h
};

/* ---------------- Strichfigur ---------------- */
const LIMBS = [[1,2],[2,3],[3,4],[2,5],[5,6],[1,7],[7,8],[1,9],[9,10]];
const anims = new WeakMap();
function drawFigure(ex, el) {
  cancelAnimationFrame(anims.get(el) || 0);
  const lines = LIMBS.map(() => `<line stroke-width="4" stroke-linecap="round"/>`).join("");
  let grid = "";
  for (let x = 10; x <= 230; x += 20) grid += `<line x1="${x}" y1="152" x2="${120 + (x - 120) * 1.6}" y2="165" stroke="#14222a"/>`;
  el.innerHTML = `<svg viewBox="0 0 240 165" role="img" aria-label="Animation: ${ex.name}">
    <defs><filter id="fg-${ex.id}" x="-20%" y="-20%" width="140%" height="140%"><feGaussianBlur stdDeviation="2.2"/><feMerge><feMergeNode/><feMergeNode in="SourceGraphic"/></feMerge></filter></defs>
    ${grid}<line x1="6" y1="152" x2="234" y2="152" stroke="#1d3038" stroke-width="1"/>
    ${(ex.prop || []).map(([x1, y1, x2, y2]) => `<line x1="${x1}" y1="${y1}" x2="${x2}" y2="${y2}" stroke="#a8dde6" stroke-opacity="0.35" stroke-width="3" stroke-linecap="round"/>`).join("")}
    <g stroke="var(--${ex.cat})" fill="none" filter="url(#fg-${ex.id})">${lines}<circle r="9" stroke-width="3" fill="#04070a"/></g></svg>`;
  const svg = el.querySelector("svg");
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
    if (!reduce) anims.set(el, requestAnimationFrame(frame));
  }
  anims.set(el, requestAnimationFrame(frame));
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
  // Eine echte Baseline schlägt immer eine leere; sonst gewinnt der neuere Stand
  if (remote.trainer) {
    const rHas = (remote.trainer.baselineDate || 0) > 0, lHas = (trainer.baselineDate || 0) > 0;
    if ((rHas && !lHas) || (rHas === lHas && (remote.trainer.updated || 0) > (trainer.updated || 0))) { trainer = remote.trainer; save(KEY.trainer, trainer); }
  }
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
  const payload = { version: 2, exported: new Date().toISOString(), entries: log, deleted, trainer };
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
  renderRecordEdit(); $("recSaveInfo").textContent = "";
  $("recSettingsInfo").textContent = trainer.baselineDate
    ? `Letzter Rekordtag: ${new Date(trainer.baselineDate).toLocaleDateString("de-DE")}. Nächster in ${daysToRecord()} Tagen.`
    : "Noch keine Baseline gemessen.";
  $("dataInfo").textContent = `${log.length} Einträge auf diesem Gerät.`;
  $("undoConfirm").hidden = true;
  $("undoBtn").disabled = !log.length;
}
$("recNow").onclick = () => show("record");
function renderRecordEdit() {
  $("recEdit").innerHTML = MARKERS.map((m) => {
    const v = trainer.baseline && trainer.baseline[m.id];
    return `<label class="field">${m.label.toUpperCase()}${m.unit === "sec" ? " (SEKUNDEN)" : ""}` +
      `<input type="number" inputmode="numeric" min="1" id="re-${m.id}" value="${v || ""}" placeholder="${m.fallback} (Schätzwert)"></label>`;
  }).join("");
}
$("recSave").onclick = () => {
  const b = { ...(trainer.baseline || {}) };
  MARKERS.forEach((m) => { const v = parseInt($("re-" + m.id).value, 10); if (v > 0) b[m.id] = v; });
  trainer.baseline = b;
  if (!trainer.baselineDate) trainer.baselineDate = Date.now();
  // Ziele neu aus den Rekorden berechnen, Wochenrhythmus bleibt
  pool().forEach((ex) => {
    const old = trainer.targets[ex.id];
    trainer.targets[ex.id] = { t: roundTarget(ex, estMax(ex) * WORK_FRACTION), reviewed: old ? old.reviewed : Date.now(), change: 0 };
  });
  saveTrainer();
  $("recSaveInfo").textContent = "Gespeichert. Ziele neu berechnet.";
  if (backupCfg.token) backupNow().catch(() => {});
};
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
let lastDeg = -1;
Body3D.init($("bodyCanvas"), (a) => {
  const deg = ((Math.round((a * 180) / Math.PI) % 360) + 360) % 360;
  if (deg !== lastDeg) { lastDeg = deg; $("hudB").textContent = `ROT ${String(deg).padStart(3, "0")}°`; }
}, (m) => { selectMuscle(m); });
show("home");
// Erschöpfung klingt mit der Zeit ab: Anzeige jede Minute auffrischen
setInterval(() => { if (!$("home").hidden) renderFatigue(); }, 60000);
document.addEventListener("visibilitychange", () => { if (document.visibilityState === "visible" && !$("home").hidden) { weeklyReview(); renderHome(); } });
maybeAutoBackup();
