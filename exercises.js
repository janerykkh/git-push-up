// Übungs-Pool von git push-up.
//
// Neue Übung hinzufügen = neuen Eintrag in EXERCISES anlegen. Felder:
//   id        eindeutiger Kurzname (nie ändern, sonst passt der Verlauf nicht mehr)
//   name      Anzeigename
//   cat       "beine" | "druecken" | "ziehen" | "rumpf"
//   unit      "reps" (Wiederholungen) oder "sec" (Sekunden halten)
//   base      Startziel beim ersten Mal
//   marker    welcher Rekordtag-Test das Maximum dieser Übung bestimmt
//   factor    Maximum dieser Übung ≈ Marker-Maximum × factor (Faustwert)
//   step      kleinste Steigerung (Wiederholungen bzw. Sekunden)
//   side      true = Ziel gilt pro Seite (zählt in der Statistik doppelt)
//   equipment null = ohne Geräte, sonst z.B. "hanteln" (erscheint dann als Schalter in den Einstellungen)
//   retired   true = kommt nicht mehr dran, zählt aber weiter im Verlauf
//   note      optionaler Warnhinweis
//   cue       Ausführungshinweis
//   muscles   { muskel: Gewicht }  1 = Hauptmuskel, 0.5 = Nebenmuskel, 0.25 = hilft mit
//   a, b      zwei Posen der Strichfigur (Seitenansicht, Boden bei y=150), die Animation pendelt zwischen ihnen.
//             Gelenk-Reihenfolge: Kopf, Hals, Hüfte, Knie1, Fuß1, Knie2, Fuß2, Ellbogen1, Hand1, Ellbogen2, Hand2

const CATEGORIES = {
  beine:    { label: "Beine" },
  druecken: { label: "Drücken" },
  ziehen:   { label: "Ziehen" },
  rumpf:    { label: "Rumpf" },
};

// Muskelgruppen für das Körpermodell
const MUSCLES = {
  chest:      "Brust",
  frontDelt:  "Schulter vorne",
  rearDelt:   "Schulter hinten",
  biceps:     "Bizeps",
  triceps:    "Trizeps",
  upperBack:  "Oberer Rücken",
  lats:       "Latissimus",
  abs:        "Bauch",
  obliques:   "Seitlicher Bauch",
  lowerBack:  "Unterer Rücken",
  glutes:     "Po",
  quads:      "Oberschenkel vorne",
  hamstrings: "Oberschenkel hinten",
  calves:     "Waden",
};

// 3 Sekunden Halten zählen wie 1 Wiederholung
const SECONDS_PER_REP = 3;

// ---------------- Trainer-Modell ----------------
// Arbeitsziel = 60 % des geschätzten Maximums: deutlich vor dem Muskelversagen, also casual und schulterfreundlich.
// Der Trainingseffekt kommt über die Häufigkeit über den Tag und die Woche, nicht über einzelne harte Sätze.
const WORK_FRACTION = 0.6;

// Erschöpfung: Ein Satz erschöpft einen Muskel um  Gewicht × (gemacht / Maximum) / FULL_EFFORT.
// Bei 1.8 bringen etwa drei Sätze à 60 % den Hauptmuskel auf 100 %.
const FULL_EFFORT = 1.8;

// Erholungszeit in Stunden, bis ein voll erschöpfter Muskel wieder fast frisch ist (unter 10 %).
// Faustwerte aus der Trainingswissenschaft: große Muskeln und Beine 48 h, Schultern und Arme 36 h,
// Rumpf und Waden erholen sich schneller (24–30 h).
const RECOVERY_HOURS = {
  chest: 48, frontDelt: 36, rearDelt: 36, biceps: 36, triceps: 36,
  upperBack: 48, lats: 48, abs: 24, obliques: 24, lowerBack: 36,
  glutes: 48, quads: 48, hamstrings: 48, calves: 30,
};

// Rekordtag: vier Markertests, alle 28 Tage. Jede Übung leitet ihr Maximum aus einem Marker ab (factor = Faustwert).
const RECORD_EVERY_DAYS = 28;
const MARKERS = [
  { id: "pushup",   label: "Liegestütze",  unit: "reps", fallback: 15,
    how: "So viele saubere Liegestütze wie möglich am Stück. Aufhören, sobald die Hüfte durchhängt oder die Schulter sich unsicher anfühlt." },
  { id: "squat",    label: "Kniebeugen",   unit: "reps", fallback: 25,
    how: "So viele Kniebeugen wie möglich am Stück, Oberschenkel mindestens parallel zum Boden." },
  { id: "plank",    label: "Unterarmstütz", unit: "sec", fallback: 45,
    how: "So lange halten wie möglich. Ende, sobald das Becken absackt oder nach oben wandert." },
  { id: "superman", label: "Superman",     unit: "sec", fallback: 40,
    how: "Arme und Beine angehoben halten, so lange es sauber geht." },
];

const STAND = [[120,28],[120,44],[120,95],[121,122],[121,150],[119,122],[119,150],[121,70],[121,94],[119,70],[119,94]];
const PLANK = [[176,94],[162,102],[106,124],[78,136],[50,148],[78,136],[50,148],[164,126],[165,150],[166,126],[167,150]];

const EXERCISES = [
  { id: "squat", marker: "squat", factor: 1.0, name: "Kniebeugen", cat: "beine", unit: "reps", base: 12, step: 1, equipment: null,
    cue: "Füße schulterbreit, Po nach hinten, Knie über die Zehen. Unten kurz halten.",
    muscles: { quads: 1, glutes: 1, hamstrings: 0.5, lowerBack: 0.25, calves: 0.25, abs: 0.25 },
    a: [[120,28],[120,44],[120,95],[121,122],[121,150],[119,122],[119,150],[136,56],[156,56],[134,58],[154,58]],
    b: [[124,60],[118,74],[100,116],[132,120],[124,150],[130,121],[122,150],[136,80],[158,80],[134,82],[156,82]] },

  { id: "lunge", marker: "squat", factor: 0.5, name: "Ausfallschritt rückwärts", cat: "beine", unit: "reps", base: 8, step: 1, side: true, equipment: null,
    cue: "Ein Bein weit nach hinten setzen, hinteres Knie fast zum Boden. Oberkörper aufrecht.",
    muscles: { quads: 1, glutes: 1, hamstrings: 0.5, calves: 0.25, obliques: 0.25 },
    a: STAND,
    b: [[116,50],[116,66],[114,114],[138,118],[140,150],[96,142],[74,150],[118,90],[120,112],[114,90],[112,112]] },

  { id: "bridge", marker: "squat", factor: 0.55, name: "Einbeinige Glute Bridge", cat: "beine", unit: "reps", base: 10, step: 1, side: true, equipment: null,
    cue: "Rückenlage, ein Fuß aufgestellt, das andere Bein gestreckt. Becken hoch, Po fest anspannen.",
    muscles: { glutes: 1, hamstrings: 1, lowerBack: 0.5, abs: 0.25 },
    a: [[40,138],[56,142],[110,146],[138,120],[150,150],[142,140],[172,134],[76,148],[98,149],[76,148],[98,149]],
    b: [[40,138],[56,142],[114,118],[144,114],[150,150],[160,104],[192,94],[76,148],[98,149],[76,148],[98,149]] },

  { id: "pushup", marker: "pushup", factor: 1.0, name: "Liegestütze", cat: "druecken", unit: "reps", base: 8, step: 1, equipment: null,
    cue: "Körper wie ein Brett, Ellbogen etwa 45° am Körper. Langsam runter, kontrolliert hoch.",
    muscles: { chest: 1, triceps: 1, frontDelt: 0.5, abs: 0.5 },
    a: [[176,94],[162,102],[106,124],[78,136],[50,148],[78,136],[50,148],[164,126],[165,150],[166,126],[167,150]],
    b: [[178,124],[162,130],[106,139],[78,143],[50,148],[78,143],[50,148],[142,134],[165,150],[144,134],[167,150]] },

  { id: "closepush", marker: "pushup", factor: 0.45, name: "Enge Liegestütze", cat: "druecken", unit: "reps", base: 6, step: 1, equipment: null,
    cue: "Hände knapp schulterbreit, Ellbogen streifen beim Runtergehen die Rippen. Fokus auf den Trizeps.",
    muscles: { triceps: 1, chest: 0.5, frontDelt: 0.5, abs: 0.5 },
    a: [[176,94],[162,102],[106,124],[78,136],[50,148],[78,136],[50,148],[160,126],[160,150],[162,126],[162,150]],
    b: [[176,124],[160,130],[106,139],[78,143],[50,148],[78,143],[50,148],[136,138],[160,150],[138,138],[162,150]] },

  // Aus dem Pool genommen (retired), bleibt aber für den Verlauf erhalten
  { id: "pike", marker: "pushup", factor: 0.4, name: "Pike Push-ups", cat: "druecken", unit: "reps", base: 5, step: 1, equipment: null, retired: true,
    note: "Nur wenn sich die Schulter sicher anfühlt. Bei Unsicherheit lieber Liegestütze.",
    cue: "Po hoch, Körper wie ein umgedrehtes V. Kopf zwischen den Händen Richtung Boden senken.",
    muscles: { frontDelt: 1, triceps: 1, upperBack: 0.5, chest: 0.25 },
    a: [[164,116],[152,108],[110,84],[86,117],[62,150],[88,117],[64,150],[158,130],[162,150],[160,130],[164,150]],
    b: [[166,140],[154,132],[110,90],[86,120],[62,150],[88,120],[64,150],[140,134],[162,150],[142,134],[164,150]] },

  { id: "superman", marker: "superman", factor: 1.0, name: "Superman", cat: "ziehen", unit: "sec", base: 20, step: 5, equipment: null,
    cue: "Bauchlage, Arme lang nach vorne. Arme und Beine gleichzeitig anheben und halten.",
    muscles: { lowerBack: 1, glutes: 0.5, upperBack: 0.5, rearDelt: 0.25, hamstrings: 0.25 },
    a: [[184,138],[170,142],[110,146],[80,147],[50,148],[80,147],[50,148],[192,143],[214,143],[192,144],[214,144]],
    b: [[184,126],[168,134],[110,146],[80,142],[50,134],[80,143],[50,136],[190,128],[212,120],[190,129],[212,121]] },

  { id: "ytw", marker: "superman", factor: 0.2, name: "Y-T-W-Raises", cat: "ziehen", unit: "reps", base: 5, step: 1, equipment: null,
    cue: "Bauchlage, Stirn knapp über dem Boden. Arme als Y, dann T, dann W anheben. Eine Runde = Y + T + W.",
    muscles: { rearDelt: 1, upperBack: 1, lats: 0.25, lowerBack: 0.25 },
    a: [[184,136],[170,141],[110,146],[80,147],[50,148],[80,147],[50,148],[150,138],[128,138],[150,139],[128,139]],
    b: [[184,136],[170,141],[110,146],[80,147],[50,148],[80,147],[50,148],[190,126],[214,118],[178,124],[196,108]] },

  { id: "birddog", marker: "plank", factor: 0.2, name: "Superman Plank", cat: "rumpf", unit: "reps", base: 6, step: 1, side: true, equipment: null,
    cue: "Hoher Stütz. Diagonal einen Arm nach vorne und das andere Bein nach hinten strecken, Becken bleibt ruhig.",
    muscles: { abs: 1, lowerBack: 0.5, glutes: 0.5, frontDelt: 0.5, obliques: 0.5 },
    a: PLANK,
    b: [[176,94],[162,102],[106,124],[78,136],[50,148],[78,118],[46,112],[164,126],[165,150],[188,100],[214,98]] },

  { id: "plank", marker: "plank", factor: 1.0, name: "Unterarmstütz", cat: "rumpf", unit: "sec", base: 30, step: 5, equipment: null,
    cue: "Unterarme unter den Schultern, Körper eine gerade Linie. Bauch und Po fest, ruhig weiteratmen.",
    muscles: { abs: 1, obliques: 0.5, frontDelt: 0.25, glutes: 0.25, quads: 0.25 },
    a: [[176,108],[162,116],[106,130],[78,139],[50,148],[78,139],[50,148],[160,148],[184,148],[162,148],[186,148]],
    b: [[176,106],[162,114],[106,127],[78,137],[50,148],[78,137],[50,148],[160,148],[184,148],[162,148],[186,148]] },

  { id: "sideplank", marker: "plank", factor: 0.5, name: "Seitstütz", cat: "rumpf", unit: "sec", base: 20, step: 5, side: true, equipment: null,
    cue: "Unterarm unter der Schulter, Körper eine Linie von Kopf bis Fuß. Becken nicht absacken lassen.",
    muscles: { obliques: 1, abs: 0.5, glutes: 0.25, frontDelt: 0.25 },
    a: [[172,100],[160,108],[106,134],[78,142],[50,148],[78,143],[50,149],[160,148],[184,148],[132,112],[110,128]],
    b: [[172,92],[160,100],[106,124],[78,137],[50,148],[78,138],[50,149],[160,148],[184,148],[132,104],[110,118]] },

  { id: "deadbug", marker: "plank", factor: 0.25, name: "Dead Bug", cat: "rumpf", unit: "reps", base: 6, step: 1, side: true, equipment: null,
    cue: "Rückenlage, Arme zur Decke, Knie 90°. Unteren Rücken in den Boden drücken, gegengleich Arm und Bein strecken.",
    muscles: { abs: 1, obliques: 0.5, quads: 0.25 },
    a: [[42,140],[58,143],[114,146],[114,114],[144,114],[116,114],[146,114],[60,120],[60,96],[62,120],[62,96]],
    b: [[42,140],[58,143],[114,146],[114,114],[144,114],[146,138],[180,140],[60,120],[60,96],[40,134],[18,138]] },
];
