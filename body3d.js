// Drehendes Wireframe-Körpermodell. Jede Muskelgruppe ist ein Ellipsoid aus Ringen;
// je mehr sie trainiert wurde, desto heller leuchtet sie phosphorgrün.
"use strict";

const Body3D = (() => {
  // [name | null, x, y, z, rx, ry, rz, spiegeln]
  // Koordinaten: x nach rechts, y nach unten (0 = Scheitel, 350 = Boden), z nach vorne
  const PARTS = [
    [null, 0, 32, 0, 15, 18, 16],            // Kopf
    [null, 0, 55, 0, 7, 8, 7],               // Hals
    [null, 56, 160, 0, 6, 21, 6, true],      // Unterarm
    [null, 59, 190, 0, 5, 7, 4, true],       // Hand
    [null, 0, 182, 0, 25, 11, 15],           // Becken
    [null, 13, 305, 3, 8, 29, 8, true],      // Schienbein
    [null, 14, 342, 7, 7, 4, 13, true],      // Fuß
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

  // Ringe (Breitengrade + Längengrade) eines Einheits-Ellipsoids, einmal vorberechnet
  const SEG = 18;
  const RINGS = [];
  [-0.6, -0.2, 0.2, 0.6].forEach((lat) => {
    const y = Math.sin(lat * Math.PI / 2), rr = Math.cos(lat * Math.PI / 2);
    RINGS.push([...Array(SEG + 1)].map((_, i) => { const a = (i / SEG) * 2 * Math.PI; return [Math.cos(a) * rr, y, Math.sin(a) * rr]; }));
  });
  [0, 1, 2].forEach((k) => {
    const lon = (k / 3) * Math.PI;
    RINGS.push([...Array(SEG + 1)].map((_, i) => { const a = (i / SEG) * 2 * Math.PI; return [Math.cos(a) * Math.cos(lon), Math.sin(a), Math.cos(a) * Math.sin(lon)]; }));
  });

  let canvas, ctx, W = 0, H = 0, dpr = 1;
  let angle = -0.5, vel = 0.0035, dragging = false, lastX = 0, onAngle = null;
  let ratio = {};
  const reduce = matchMedia("(prefers-reduced-motion: reduce)").matches;

  function resize() {
    const r = canvas.getBoundingClientRect();
    dpr = Math.min(2, window.devicePixelRatio || 1);
    W = r.width; H = r.height;
    canvas.width = Math.round(W * dpr); canvas.height = Math.round(H * dpr);
  }

  const WIRE = [168, 221, 230], PHOS = [126, 240, 166];
  function project(p, cosA, sinA, scale, cx, cy) {
    // Drehen um y, dann leicht von oben schauen
    let x = p[0] * cosA + p[2] * sinA;
    let z = -p[0] * sinA + p[2] * cosA;
    let y = p[1] - 185;
    const tilt = 0.18, ct = Math.cos(tilt), st = Math.sin(tilt);
    const y2 = y * ct - z * st, z2 = y * st + z * ct;
    const f = 700 / (700 - z2 * 1.2);
    return [cx + x * scale * f, cy + y2 * scale * f, z2];
  }

  function draw() {
    if (!ctx) return;
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, W, H);
    const scale = Math.min(W / 260, H / 400);
    const cx = W / 2, cy = H * 0.5;
    const cosA = Math.cos(angle), sinA = Math.sin(angle);

    // Bodengitter
    ctx.lineWidth = 1;
    ctx.strokeStyle = "rgba(168,221,230,0.10)";
    for (let i = -4; i <= 4; i++) {
      const a = project([i * 25, 350, -100], cosA, sinA, scale, cx, cy), b = project([i * 25, 350, 100], cosA, sinA, scale, cx, cy);
      const c = project([-100, 350, i * 25], cosA, sinA, scale, cx, cy), d = project([100, 350, i * 25], cosA, sinA, scale, cx, cy);
      ctx.beginPath(); ctx.moveTo(a[0], a[1]); ctx.lineTo(b[0], b[1]); ctx.moveTo(c[0], c[1]); ctx.lineTo(d[0], d[1]); ctx.stroke();
    }

    // Hinten zuerst zeichnen
    const order = parts.map((p) => ({ p, z: project(p.c, cosA, sinA, scale, cx, cy)[2] })).sort((a, b) => a.z - b.z);
    order.forEach(({ p }) => {
      const r = p.m ? (ratio[p.m] || 0) : -1;
      let col, alpha, glow;
      if (r < 0) { col = WIRE; alpha = 0.22; glow = 0; }
      else if (r === 0) { col = WIRE; alpha = 0.38; glow = 0; }
      else { col = WIRE.map((v, i) => Math.round(v + (PHOS[i] - v) * Math.min(1, 0.35 + r))); alpha = 0.5 + 0.5 * r; glow = 4 + 10 * r; }
      ctx.lineWidth = r > 0 ? 1 + 0.6 * r : 1;
      ctx.shadowBlur = glow; ctx.shadowColor = `rgba(${PHOS.join(",")},0.8)`;
      RINGS.forEach((ring) => {
        let prev = null;
        ring.forEach((u) => {
          const q = project([p.c[0] + u[0] * p.r[0], p.c[1] + u[1] * p.r[1], p.c[2] + u[2] * p.r[2]], cosA, sinA, scale, cx, cy);
          if (prev) {
            const depth = Math.max(0, Math.min(1, ((prev[2] + q[2]) / 2 + 60) / 120));
            ctx.strokeStyle = `rgba(${col.join(",")},${(alpha * (0.35 + 0.65 * depth)).toFixed(3)})`;
            ctx.beginPath(); ctx.moveTo(prev[0], prev[1]); ctx.lineTo(q[0], q[1]); ctx.stroke();
          }
          prev = q;
        });
      });
    });
    ctx.shadowBlur = 0;
  }

  function loop() {
    if (!dragging && !reduce) { angle += vel; vel += (0.0035 * Math.sign(vel || 1) - vel) * 0.02; }
    if (canvas.isConnected && canvas.offsetParent !== null) { draw(); if (onAngle) onAngle(angle); }
    requestAnimationFrame(loop);
  }

  function init(el, angleCb) {
    canvas = el; ctx = canvas.getContext("2d"); onAngle = angleCb;
    resize();
    new ResizeObserver(resize).observe(canvas);
    canvas.addEventListener("pointerdown", (e) => { dragging = true; lastX = e.clientX; vel = 0; canvas.setPointerCapture(e.pointerId); });
    canvas.addEventListener("pointermove", (e) => { if (!dragging) return; const dx = e.clientX - lastX; lastX = e.clientX; angle += dx * 0.012; vel = dx * 0.012; if (reduce) draw(); });
    const up = () => { dragging = false; if (Math.abs(vel) < 0.002) vel = 0.0035; };
    canvas.addEventListener("pointerup", up); canvas.addEventListener("pointercancel", up);
    requestAnimationFrame(loop);
  }
  function setLoad(r) { ratio = r; draw(); }
  return { init, setLoad };
})();
