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

## iPhone-App (Xcode)

Im Ordner `ios/` liegt die native Version (SwiftUI, ab iOS 17). Gleiche Logik wie die Web-App,
Daten lokal auf dem iPhone, Backup im selben Format in `git-push-up-private`.

1. `ios/GitPushUp.xcodeproj` in Xcode öffnen
2. Target *GitPushUp* → *Signing & Capabilities* → Team auswählen (Personal Team reicht)
3. iPhone per Kabel anschließen, als Ziel wählen, Run

Neue Swift-Dateien einfach in den Ordner `ios/GitPushUp/` legen, Xcode nimmt sie automatisch auf.
