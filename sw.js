// Netz zuerst, damit Updates sofort ankommen; ohne Netz aus dem Cache.
const CACHE = "gpu-v2";
const FILES = ["./", "index.html", "style.css", "app.js", "exercises.js", "body3d.js", "manifest.webmanifest", "icon-180.png", "icon-192.png", "icon-512.png"];
self.addEventListener("install", (e) => { e.waitUntil(caches.open(CACHE).then((c) => c.addAll(FILES))); self.skipWaiting(); });
self.addEventListener("activate", (e) => { e.waitUntil(caches.keys().then((ks) => Promise.all(ks.filter((k) => k !== CACHE).map((k) => caches.delete(k))))); self.clients.claim(); });
self.addEventListener("fetch", (e) => {
  const u = new URL(e.request.url);
  if (e.request.method !== "GET" || u.hostname === "api.github.com") return;
  e.respondWith(
    fetch(e.request).then((res) => {
      if (res.ok && (u.origin === location.origin || u.hostname.endsWith("gstatic.com") || u.hostname.endsWith("googleapis.com"))) {
        const copy = res.clone(); caches.open(CACHE).then((c) => c.put(e.request, copy));
      }
      return res;
    }).catch(() => caches.match(e.request, { ignoreSearch: true }))
  );
});
