import Foundation

enum MonitorTime {
    private static let amsterdam = TimeZone(identifier: "Europe/Amsterdam") ?? .gmt

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = amsterdam
        return calendar
    }

    static func clock(_ value: String) -> Int {
        let parts = value.split(separator: ":").compactMap { Int($0) }
        return parts.count == 2 ? parts[0] * 60 + parts[1] : 0
    }

    static func inCheckWindow(_ plan: MonitorPlan, now: Date = Date()) -> Bool {
        guard plan.activeDays.contains(calendar.component(.weekday, from: now)) else { return false }
        let minutes = clock(timeString(now))
        return minutes >= clock(plan.firstCheck) && minutes <= clock(plan.lastCheck)
    }

    static func timeString(_ date: Date) -> String {
        formatted(date, format: "HH:mm")
    }

    static func dateString(_ date: Date) -> String {
        formatted(date, format: "yyyy-MM-dd")
    }

    static func apiDateTime(_ time: String) -> String {
        let parts = time.split(separator: ":").compactMap { Int($0) }
        let date = calendar.date(
            bySettingHour: parts.first ?? 0,
            minute: parts.count > 1 ? parts[1] : 0,
            second: 0,
            of: Date()
        ) ?? Date()
        return ISO8601DateFormatter().string(from: date)
    }

    private static func formatted(_ date: Date, format: String) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = amsterdam
        formatter.dateFormat = format
        return formatter.string(from: date)
    }
}
