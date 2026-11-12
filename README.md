# git push-up

Eine zufällige Körpergewichtsübung pro Wartepause, wenn Claude rechnet oder der Build läuft.

- Großer Knopf **ÜBUNG** → zufällige Übung aus einer anderen Kategorie als zuletzt
- Animation, Ziel und Hinweis zur Ausführung
- **Geschafft** erhöht das Ziel beim nächsten Mal, **Nicht geschafft** übernimmt, was du wirklich gemacht hast
- Statistik mit Körpermodell (Tag / Woche / Monat / Jahr), Serie, Erfolgsquote und Fortschritt pro Übung
- Verlauf liegt auf dem Gerät, tägliches Backup ins private Repo `git-push-up-private`

## Neue Übung hinzufügen

Einen Eintrag in `exercises.js` ergänzen. Die Felder sind oben in der Datei erklärt.
Übungen mit `equipment: "hanteln"` erscheinen erst, wenn der Schalter in den Einstellungen an ist.

## Dateien

| Datei | Inhalt |
|---|---|
| `index.html` | Bildschirme |
| `style.css` | Aussehen, helles und dunkles Design |
| `exercises.js` | Übungen, Muskelgruppen, Posen |
| `app.js` | Logik, Statistik, Backup |
| `sw.js` | Offline-Modus |

## Neue Version veröffentlichen

`BUILD` in `index.html`, die `?v=`-Nummern dort und `version.json` auf dieselbe neue Zahl setzen.
Die App merkt beim Öffnen, dass `version.json` neuer ist, und lädt sich einmal neu.
