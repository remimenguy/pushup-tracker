import Foundation
import XCTest
@testable import PushupTracker

final class WorkoutStoreTests: XCTestCase {
    @MainActor
    func testPersistsAndGroupsSessionsInLocalDays() throws {
        let file = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appending(path: "sessions.json")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let store = WorkoutStore(file: file)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Paris"))
        let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 30, hour: 0, minute: 10)))
        let earlier = date.addingTimeInterval(-1_200)
        let first = Workout(id: UUID(), date: date, reps: 6)
        try store.add(first)
        try store.add(first)
        try store.add(Workout(id: UUID(), date: date.addingTimeInterval(600), reps: 9))
        try store.add(Workout(id: UUID(), date: earlier, reps: 3))
        try store.add(Workout(id: UUID(), date: date, reps: 0))

        let reopened = WorkoutStore(file: file)
        let days = reopened.days(3, endingAt: date, calendar: calendar)
        XCTAssertEqual(days.map(\.total), [0, 3, 15])
        XCTAssertEqual(reopened.workouts.count, 3)
    }

    @MainActor
    func testFailedWriteDoesNotChangeInMemoryHistory() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try Data().write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let store = WorkoutStore(file: file.appending(path: "sessions.json"))
        XCTAssertThrowsError(try store.add(Workout(id: UUID(), date: Date(), reps: 6)))
        XCTAssertTrue(store.workouts.isEmpty)
    }
}
