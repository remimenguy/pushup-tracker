import Foundation
import Observation

struct Workout: Codable, Identifiable {
    let id: UUID
    let date: Date
    let reps: Int
}

struct WorkoutDay: Identifiable {
    let date: Date
    let total: Int
    var id: Date { date }
}

@MainActor
@Observable
final class WorkoutStore {
    private(set) var workouts: [Workout] = []
    private(set) var loadError: Error?
    private let file: URL

    init(file: URL = URL.applicationSupportDirectory.appending(path: "sessions.json")) {
        self.file = file
        do {
            workouts = try JSONDecoder().decode([Workout].self, from: Data(contentsOf: file))
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            // A fresh installation has no history file.
        } catch {
            loadError = error
        }
    }

    func add(_ workout: Workout) throws {
        guard workout.reps > 0, !workouts.contains(where: { $0.id == workout.id }) else { return }
        if let loadError { throw loadError }
        let updated = workouts + [workout]
        let data = try JSONEncoder().encode(updated)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: file, options: .atomic)
        workouts = updated
    }

    func dailyTotals(calendar: Calendar = .current) -> [Date: Int] {
        workouts.reduce(into: [:]) { totals, workout in
            totals[calendar.startOfDay(for: workout.date), default: 0] += workout.reps
        }
    }

    func days(_ count: Int, endingAt date: Date, calendar: Calendar = .current) -> [WorkoutDay] {
        guard count > 0 else { return [] }
        let end = calendar.startOfDay(for: date)
        let totals = dailyTotals(calendar: calendar)
        return (1 - count...0).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: end).map { day in
                WorkoutDay(date: day, total: totals[day, default: 0])
            }
        }
    }
}
