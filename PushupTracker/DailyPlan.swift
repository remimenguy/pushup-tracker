import Foundation
import Observation
import UserNotifications

struct DailyPlan: Codable, Equatable {
    var goal = 10
    var minutes = 10
    var hour = 18
    var minute = 0

    var reminderTime: Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: .now) ?? .now
    }

    mutating func setReminderTime(_ time: Date) {
        let components = Calendar.current.dateComponents([.hour, .minute], from: time)
        hour = components.hour ?? hour
        minute = components.minute ?? minute
    }
}

@MainActor
@Observable
final class PlanStore {
    private(set) var plan: DailyPlan
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        plan = defaults.data(forKey: "dailyPlan")
            .flatMap { try? JSONDecoder().decode(DailyPlan.self, from: $0) } ?? DailyPlan()
    }

    func save(_ updated: DailyPlan) {
        guard let data = try? JSONEncoder().encode(updated) else { return }
        defaults.set(data, forKey: "dailyPlan")
        plan = updated
    }
}

@MainActor
struct DailyReminder {
    enum ReminderError: Error { case denied }

    private static let identifier = "pompes.daily"
    private let center = UNUserNotificationCenter.current()

    func isScheduled() async -> Bool {
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            return false
        }
        return await center.pendingNotificationRequests().contains { $0.identifier == Self.identifier }
    }

    func update(enabled: Bool, plan: DailyPlan) async throws {
        guard enabled else {
            center.removePendingNotificationRequests(withIdentifiers: [Self.identifier])
            center.removeDeliveredNotifications(withIdentifiers: [Self.identifier])
            return
        }
        guard try await center.requestAuthorization(options: [.alert, .sound]) else {
            throw ReminderError.denied
        }

        let content = UNMutableNotificationContent()
        content.title = "C’est l’heure des pompes"
        content.body = "Ton objectif du jour : \(repText(plan.goal)) en \(plan.minutes) min maximum."
        content.sound = .default
        let time = DateComponents(hour: plan.hour, minute: plan.minute)
        let trigger = UNCalendarNotificationTrigger(dateMatching: time, repeats: true)
        try await center.add(UNNotificationRequest(identifier: Self.identifier, content: content, trigger: trigger))
    }
}

func repText(_ count: Int) -> String {
    "\(count) \(count == 1 ? "pompe" : "pompes")"
}
