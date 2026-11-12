// Drehendes Wireframe-Körpermodell. Jede Muskelgruppe ist ein Ellipsoid aus Ringen;
// je stärker sie heute ausgelastet ist, desto heller leuchtet sie phosphorgrün.
// Auf älteren iPhones schnell genug: pro Körperteil nur wenige Pfade, kein Canvas-Schatten.
"use strict";

const Body3D = (() => {
  // [name | null, x, y, z, rx, ry, rz, spiegeln]  x rechts, y unten (350 = Boden), z vorne
  const PARTS = [
    [null, 0, 32, 0, 15, 18, 16], [null, 0, 55, 0, 7, 8, 7],
    [null, 56, 160, 0, 6, 21, 6, true], [null, 59, 190, 0, 5, 7, 4, true],
    [null, 0, 182, 0, 25, 11, 15],
    [null, 13, 305, 3, 8, 29, 8, true], [null, 14, 342, 7, 7, 4, 13, true],
    ["chest", 16, 94, 15, 15, 12, 7, true],
    ["frontDelt", 36, 79, 6, 10, 11, 9, true],
    ["rearDelt", 36, 79, -7, 10, 11, 8, true],
    ["biceps", 48, 118, 5, 7, 18, 6, true],
    ["triceps", 48, 118, -5, 7, 18, 6, true],
    ["abs", 0, 140, 16, 12, 31, 6],
    ["obliques", 22, 143, 10, 7, 22, 8, true],
    ["upperBack", 0, 88, -14, 25, 22, 8],
    ["lats", 20, 126, -12, 11, 24, 8, true],
    ["lowerBack", 0, 152, -15, 12, 17, 6],
    ["glutes", 12, 190, -12, 13, 15, 10, true],
    ["quads", 13, 233, 6, 12, 37, 10, true],
    ["hamstrings", 13, 244, -6, 11, 31, 9, true],
    ["calves", 13, 302, -6, 9, 25, 8, true],
  ];
  const parts = [];
  PARTS.forEach(([m, x, y, z, rx, ry, rz, mir]) => {
    parts.push({ m, c: [x, y, z], r: [rx, ry, rz] });
    if (mir) parts.push({ m, c: [-x, y, z], r: [rx, ry, rz] });
  });

  const SEG = 14;
  const RINGS = [];
  [-0.55, 0, 0.55].forEach((lat) => {
    const y = Math.sin(lat * Math.PI / 2), rr = Math.cos(lat * Math.PI / 2);
    RINGS.push([...Array(SEG + 1)].map((_, i) => { const a = (i / SEG) * 2 * Math.PI; return [Math.cos(a) * rr, y, Math.sin(a) * rr]; }));
  });
  [0, 1, 2].forEach((k) => {
    const lon = (k / 3) * Math.PI;
    RINGS.push([...Array(SEG + 1)].map((_, i) => { const a = (i / SEG) * 2 * Math.PI; return [Math.cos(a) * Math.cos(lon), Math.sin(a), Math.cos(a) * Math.sin(lon)]; }));
  });

  let canvas, ctx, W = 0, H = 0, dpr = 1;
  let angle = -0.5, spin = 0.32; // Radiant pro Sekunde
  let dragging = false, lastX = 0, downX = 0, downY = 0, moved = 0, dragVel = 0;
  let ratio = {}, selected = null, onAngle = null, onPick = null;
  let lastT = 0, dirty = true;
  let hits = [];
  const reduce = matchMedia("(prefers-reduced-motion: reduce)").matches;
  const autoSpin = reduce ? 0.12 : 0.32; // auch bei "Bewegung reduzieren" langsam drehen

  function resize() {
    const r = canvas.getBoundingClientRect();
    dpr = Math.min(2, window.devicePixelRatio || 1);
    W = r.width; H = r.height;
    canvas.width = Math.round(W * dpr); canvas.height = Math.round(H * dpr);
    dirty = true;
  }

  const TILT_C = Math.cos(0.18), TILT_S = Math.sin(0.18);
  function project(x0, y0, z0, cosA, sinA, scale, cx, cy, out) {
    const x = x0 * cosA + z0 * sinA;
    const z = -x0 * sinA + z0 * cosA;
    const y = y0 - 185;
    const y2 = y * TILT_C - z * TILT_S, z2 = y * TILT_S + z * TILT_C;
    const f = 700 / (700 - z2 * 1.2);
    out[0] = cx + x * scale * f; out[1] = cy + y2 * scale * f; out[2] = z2;
    return out;
  }

  const q = [0, 0, 0], c0 = [0, 0, 0];
  function strokePart(p, cosA, sinA, scale, cx, cy, front) {
    ctx.beginPath();
    for (const ring of RINGS) {
      let pen = false;
      for (const u of ring) {
        project(p.c[0] + u[0] * p.r[0], p.c[1] + u[1] * p.r[1], p.c[2] + u[2] * p.r[2], cosA, sinA, scale, cx, cy, q);
        const isFront = q[2] > p.zc - 0.5;
        if (isFront !== front) { pen = false; continue; }
        if (pen) ctx.lineTo(q[0], q[1]); else { ctx.moveTo(q[0], q[1]); pen = true; }
      }
    }
    ctx.stroke();
  }

  function colorFor(p) {
    if (!p.m) return { rgb: "168,221,230", a: 0.2, glow: 0 };
    const r = Math.min(1, ratio[p.m] || 0);
    if (p.m === selected) return { rgb: "242,168,90", a: 0.95, glow: 1 };
    if (r <= 0) return { rgb: "168,221,230", a: 0.34, glow: 0 };
    const mix = (a, b) => Math.round(a + (b - a) * Math.min(1, 0.3 + r));
    return { rgb: `${mix(168, 126)},${mix(221, 240)},${mix(230, 166)}`, a: 0.45 + 0.5 * r, glow: r };
  }

  function draw() {
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, W, H);
    const scale = Math.min(W / 260, H / 400);
    const cx = W / 2, cy = H * 0.5;
    const cosA = Math.cos(angle), sinA = Math.sin(angle);

    // Bodengitter in einem Pfad
    ctx.lineWidth = 1; ctx.strokeStyle = "rgba(168,221,230,0.10)"; ctx.beginPath();
    const a = [0, 0, 0], b = [0, 0, 0];
    for (let i = -4; i <= 4; i++) {
      project(i * 25, 350, -100, cosA, sinA, scale, cx, cy, a); project(i * 25, 350, 100, cosA, sinA, scale, cx, cy, b);
      ctx.moveTo(a[0], a[1]); ctx.lineTo(b[0], b[1]);
      project(-100, 350, i * 25, cosA, sinA, scale, cx, cy, a); project(100, 350, i * 25, cosA, sinA, scale, cx, cy, b);
      ctx.moveTo(a[0], a[1]); ctx.lineTo(b[0], b[1]);
    }
    ctx.stroke();

    // Mittelpunkte projizieren (für Sortierung und Antippen)
    hits = [];
    parts.forEach((p) => {
      project(p.c[0], p.c[1], p.c[2], cosA, sinA, scale, cx, cy, c0);
      p.zc = c0[2]; p.sx = c0[0]; p.sy = c0[1];
      if (p.m) hits.push({ m: p.m, x: c0[0], y: c0[1], z: c0[2], rx: Math.max(p.r[0], p.r[2]) * scale + 6, ry: p.r[1] * scale + 6 });
    });
    const order = parts.slice().sort((x, y) => x.zc - y.zc);

    for (const p of order) {
      const c = colorFor(p);
      // Rückseite schwach, Vorderseite kräftig; Leuchten als breiter, durchsichtiger Strich darunter
      ctx.lineWidth = 1; ctx.strokeStyle = `rgba(${c.rgb},${(c.a * 0.35).toFixed(3)})`;
      strokePart(p, cosA, sinA, scale, cx, cy, false);
      if (c.glow > 0) {
        ctx.lineWidth = 4 + 3 * c.glow; ctx.strokeStyle = `rgba(${c.rgb},${(0.10 + 0.12 * c.glow).toFixed(3)})`;
        strokePart(p, cosA, sinA, scale, cx, cy, true);
      }
      ctx.lineWidth = c.glow > 0 ? 1.3 : 1; ctx.strokeStyle = `rgba(${c.rgb},${c.a.toFixed(3)})`;
      strokePart(p, cosA, sinA, scale, cx, cy, true);
    }
    if (onAngle) onAngle(angle);
  }

  function loop(t) {
    const dt = lastT ? Math.min(0.1, (t - lastT) / 1000) : 0; lastT = t;
    const visible = canvas.offsetParent !== null && document.visibilityState === "visible";
    if (visible) {
      if (!dragging) {
        angle += spin * dt;
        spin += (autoSpin * Math.sign(spin || 1) - spin) * Math.min(1, dt * 1.5); // nach Wischen sanft zurück zur Grundgeschwindigkeit
        dirty = true;
      }
      if (dirty) { draw(); dirty = false; }
    }
    requestAnimationFrame(loop);
  }

  function pickAt(px, py) {
    let best = null;
    hits.forEach((h) => {
      const dx = (px - h.x) / h.rx, dy = (py - h.y) / h.ry, d = dx * dx + dy * dy;
      if (d <= 1 && (!best || h.z > best.z + 4 || (Math.abs(h.z - best.z) <= 4 && d < best.d))) best = { ...h, d };
    });
    return best ? best.m : null;
  }

  function init(el, angleCb, pickCb) {
    canvas = el; ctx = canvas.getContext("2d"); onAngle = angleCb; onPick = pickCb;
    resize();
    new ResizeObserver(resize).observe(canvas);
    canvas.addEventListener("pointerdown", (e) => {
      dragging = true; lastX = downX = e.clientX; downY = e.clientY; moved = 0; dragVel = 0;
      canvas.setPointerCapture(e.pointerId);
    });
    canvas.addEventListener("pointermove", (e) => {
      if (!dragging) return;
      const dx = e.clientX - lastX; lastX = e.clientX;
      moved = Math.max(moved, Math.hypot(e.clientX - downX, e.clientY - downY));
      angle += dx * 0.012; dragVel = dx * 0.012 * 60; dirty = true;
    });
    const up = (e) => {
      if (!dragging) return;
      dragging = false;
      if (moved < 8) {
        const r = canvas.getBoundingClientRect();
        const m = pickAt(e.clientX - r.left, e.clientY - r.top);
        selected = m === selected ? null : m; dirty = true;
        if (onPick) onPick(selected);
      } else if (Math.abs(dragVel) > 0.2) spin = Math.max(-6, Math.min(6, dragVel));
    };
    canvas.addEventListener("pointerup", up);
    canvas.addEventListener("pointercancel", () => { dragging = false; });
    requestAnimationFrame(loop);
  }
  function setLoad(r) { ratio = r; dirty = true; }
  function select(m) { selected = m; dirty = true; }
  return { init, setLoad, select };
})();
