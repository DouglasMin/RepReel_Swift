import Foundation
import ReelsKit

@MainActor
@Observable
public final class HistoryStore {
    private let client: APIClient

    public var sessions: [WorkoutSessionLog] = []
    public var isLoading = false
    public var errorMessage: String?

    public init(client: APIClient) {
        self.client = client
    }

    public func loadHistory() async {
        isLoading = true
        defer { isLoading = false }
        do {
            #if DEBUG
            print("[HistoryStore] Loading workout session history...")
            #endif
            sessions = try await client.sessions(limit: 50)
            #if DEBUG
            print("[HistoryStore] Loaded \(sessions.count) completed workout sessions.")
            #endif
            errorMessage = nil
        } catch is CancellationError {
            // Task cancelled
        } catch {
            guard !Task.isCancelled else { return }
            if case APIError.transport(let underlying) = error,
               (underlying as NSError).code == NSURLErrorCancelled {
                return
            }
            #if DEBUG
            print("[HistoryStore] Failed to load history: \(error)")
            #endif
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Aggregated Analytics

    public var totalVolumeKg: Double {
        sessions.compactMap { $0.volumeAnalytics?.totalVolumeKg }.reduce(0, +)
    }

    public var totalSets: Int {
        sessions.compactMap { $0.volumeAnalytics?.totalSetsCompleted }.reduce(0, +)
    }

    public var totalReps: Int {
        sessions.compactMap { $0.volumeAnalytics?.totalRepsCompleted }.reduce(0, +)
    }

    public var weeklyVolumeKg: Double {
        let sevenDaysAgo = Date().addingTimeInterval(-7 * 86400).timeIntervalSince1970
        return sessions
            .filter { Double($0.loggedAt ?? 0) >= sevenDaysAgo }
            .compactMap { $0.volumeAnalytics?.totalVolumeKg }
            .reduce(0, +)
    }

    public var weeklySessionCount: Int {
        let sevenDaysAgo = Date().addingTimeInterval(-7 * 86400).timeIntervalSince1970
        return sessions.filter { Double($0.loggedAt ?? 0) >= sevenDaysAgo }.count
    }

    public var weeklySetsCount: Int {
        let sevenDaysAgo = Date().addingTimeInterval(-7 * 86400).timeIntervalSince1970
        return sessions
            .filter { Double($0.loggedAt ?? 0) >= sevenDaysAgo }
            .compactMap { $0.volumeAnalytics?.totalSetsCompleted }
            .reduce(0, +)
    }

    // MARK: - Calendar & Date Queries

    public func sessions(on date: Date, calendar: Calendar = .current) -> [WorkoutSessionLog] {
        sessions.filter { session in
            guard let loggedAt = session.loggedAt else { return false }
            let sessionDate = Date(timeIntervalSince1970: TimeInterval(loggedAt))
            return calendar.isDate(sessionDate, inSameDayAs: date)
        }
    }

    public func hasWorkout(on date: Date, calendar: Calendar = .current) -> Bool {
        !sessions(on: date, calendar: calendar).isEmpty
    }

    public func dailyVolumeKg(on date: Date, calendar: Calendar = .current) -> Double {
        sessions(on: date, calendar: calendar)
            .compactMap { $0.volumeAnalytics?.totalVolumeKg }
            .reduce(0, +)
    }

    // MARK: - Weekly Dashboard & Streak Metrics

    public struct DailyVolumePoint: Identifiable, Sendable {
        public var id: String { dayName + "_\(date.timeIntervalSince1970)" }
        public let dayName: String
        public let date: Date
        public let volumeKg: Double
        public let isToday: Bool
        public let hasWorkout: Bool

        public init(dayName: String, date: Date, volumeKg: Double, isToday: Bool, hasWorkout: Bool) {
            self.dayName = dayName
            self.date = date
            self.volumeKg = volumeKg
            self.isToday = isToday
            self.hasWorkout = hasWorkout
        }
    }

    public var thisWeekVolumeKg: Double {
        let calendar = Calendar.current
        guard let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: Date())?.start else {
            return weeklyVolumeKg
        }
        return sessions
            .filter { Date(timeIntervalSince1970: TimeInterval($0.loggedAt ?? 0)) >= startOfWeek }
            .compactMap { $0.volumeAnalytics?.totalVolumeKg }
            .reduce(0, +)
    }

    public var lastWeekVolumeKg: Double {
        let calendar = Calendar.current
        guard let currentWeekStart = calendar.dateInterval(of: .weekOfYear, for: Date())?.start,
              let lastWeekStart = calendar.date(byAdding: .weekOfYear, value: -1, to: currentWeekStart) else {
            return 0
        }
        return sessions
            .filter {
                let d = Date(timeIntervalSince1970: TimeInterval($0.loggedAt ?? 0))
                return d >= lastWeekStart && d < currentWeekStart
            }
            .compactMap { $0.volumeAnalytics?.totalVolumeKg }
            .reduce(0, +)
    }

    public var weekOverWeekPercentage: Double? {
        guard lastWeekVolumeKg > 0 else { return nil }
        return ((thisWeekVolumeKg - lastWeekVolumeKg) / lastWeekVolumeKg) * 100.0
    }

    public var currentWeekDays: [DailyVolumePoint] {
        var calendar = Calendar.current
        calendar.locale = Locale(identifier: "ko_KR")
        let today = Date()
        guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: today) else { return [] }

        let weekdaySymbols = ["월", "화", "수", "목", "금", "토", "일"]
        var points: [DailyVolumePoint] = []

        for i in 0..<7 {
            if let dayDate = calendar.date(byAdding: .day, value: i, to: weekInterval.start) {
                let vol = dailyVolumeKg(on: dayDate, calendar: calendar)
                let isToday = calendar.isDate(dayDate, inSameDayAs: today)
                let weekdayIndex = (calendar.component(.weekday, from: dayDate) + 5) % 7
                let symbol = weekdaySymbols[min(6, max(0, weekdayIndex))]
                points.append(DailyVolumePoint(
                    dayName: symbol,
                    date: dayDate,
                    volumeKg: vol,
                    isToday: isToday,
                    hasWorkout: vol > 0
                ))
            }
        }
        return points
    }

    public var currentStreakDays: Int {
        let calendar = Calendar.current
        let today = Date()
        var streak = 0

        let startFromToday = hasWorkout(on: today, calendar: calendar)
        let startIndex = startFromToday ? 0 : 1

        for dayOffset in startIndex..<365 {
            guard let dateToCheck = calendar.date(byAdding: .day, value: -dayOffset, to: today) else { break }
            if hasWorkout(on: dateToCheck, calendar: calendar) {
                streak += 1
            } else {
                break
            }
        }
        return streak
    }
}
