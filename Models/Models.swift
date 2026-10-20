import Foundation

struct Station: Codable, Hashable, Identifiable { let code: String; let name: String; var id: String { code } }

struct MonitorPlan: Codable, Hashable, Identifiable {
    static let orderedWeekdays = [(2, "Mon"), (3, "Tue"), (4, "Wed"), (5, "Thu"), (6, "Fri"), (7, "Sat"), (1, "Sun")]

    var id = UUID()
    var departureCode = "APD"
    var destinationCode = "ASD"
    var departureFrom = "07:00"
    var departureUntil = "08:00"
    var firstCheck = "06:30"
    var lastCheck = "08:00"
    var pollMinutes = 5
    var maximumDepartures = 5
    // nil preserves the behavior of monitors saved before day selection existed.
    var monitoringDays: Set<Int>? = nil
    var activeDays: Set<Int> { monitoringDays ?? Set(1...7) }
    var daysLabel: String {
        let days = activeDays
        if days.count == 7 { return "Every day" }
        if days == Set([2, 3, 4, 5, 6]) { return "Weekdays" }
        if days == Set([1, 7]) { return "Weekends" }
        return Self.orderedWeekdays.compactMap { days.contains($0.0) ? $0.1 : nil }.joined(separator: ", ")
    }
}

struct AppSettings: Codable, Equatable {
    var ntfyTopic = ""
    // Optional so settings saved by older app versions continue to decode.
    var liveNDOVEnabled: Bool? = nil
    var usesLiveNDOV: Bool { liveNDOVEnabled == true }
}

struct Journey: Identifiable, Hashable {
    let id: String, planned: String, actual: String, destination: String, platform: String
    let cancelled: Bool, delay: Int
    var status: String { cancelled ? "Cancelled" : delay > 0 ? "+\(delay) min · expected \(actual)" : "On time" }
    var summary: String { "\(planned) → \(destination) | platform \(platform.isEmpty ? "—" : platform) | \(status)" }
}
