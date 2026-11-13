import Foundation
import UserNotifications

/// Tägliche Erinnerung: eine Nachricht am Tag zur gewählten Uhrzeit, vom Wesen.
/// Kommt nur an Tagen, an denen noch nichts gemacht wurde, und nie im Ruhemodus.
/// Läuft komplett auf dem iPhone: die nächsten sieben Tage werden im Voraus eingeplant und bei jedem
/// Öffnen der App und nach jeder Übung neu gesetzt.
extension Store {

    func enableReminders(_ on: Bool) {
        state.reminderOn = on
        save()
        guard on else { rescheduleReminders(); return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            DispatchQueue.main.async {
                if !granted { self.state.reminderOn = false; self.save() }
                self.rescheduleReminders()
            }
        }
    }

    func setReminderTime(hour: Int, minute: Int) {
        state.reminderHour = hour
        state.reminderMinute = minute
        save()
        rescheduleReminders()
    }

    func rescheduleReminders() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: (0..<8).map { "daily-\($0)" })
        guard state.reminderOn, !state.resting, let c = state.creature, c.hatched == true else { return }
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let doneToday = state.log.contains { $0.ts >= today.timeIntervalSince1970 * 1000 }
        for i in 0..<7 {
            if i == 0 && doneToday { continue }
            guard let day = cal.date(byAdding: .day, value: i, to: today),
                  let at = cal.date(bySettingHour: state.reminderHour, minute: state.reminderMinute, second: 0, of: day),
                  at > Date() else { continue }
            let content = UNMutableNotificationContent()
            content.title = c.name.uppercased()
            content.body = Self.reminderLines[(Int(at.timeIntervalSince1970 / 86400) + c.seed) % Self.reminderLines.count]
                .replacingOccurrences(of: "{n}", with: c.name)
            content.sound = .default
            let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: at)
            let req = UNNotificationRequest(identifier: "daily-\(i)",
                                            content: content,
                                            trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
            center.add(req)
        }
    }

    static let reminderLines = [
        "{n} drückt sich an die Scheibe.",
        "{n} schaut zur Tür. Eine Übung?",
        "{n} wartet. Zwei Minuten für dich?",
        "Im Glaskasten regt sich etwas.",
        "{n} hat heute noch nichts von dir gehört.",
        "Kurz was für dich tun? {n} wächst mit.",
        "{n} klopft leise ans Glas.",
    ]
}
