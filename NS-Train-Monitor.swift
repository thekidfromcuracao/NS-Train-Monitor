import SwiftUI
import AppKit
import Foundation
import Security
import CNDOV

struct Station: Codable, Hashable, Identifiable { let code: String; let name: String; var id: String { code } }

struct MonitorPlan: Codable, Hashable, Identifiable {
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
        let ordered = [(2, "Mon"), (3, "Tue"), (4, "Wed"), (5, "Thu"), (6, "Fri"), (7, "Sat"), (1, "Sun")]
        return ordered.compactMap { days.contains($0.0) ? $0.1 : nil }.joined(separator: ", ")
    }
}

struct AppSettings: Codable, Equatable {
    var ntfyTopic = ""
    // Optional so settings saved by older app versions continue to decode.
    var liveNDOVEnabled: Bool? = nil
    var usesLiveNDOV: Bool { liveNDOVEnabled == true }
}

enum NDOVConnectionState: Equatable {
    case disabled, connecting, connected, fallback
    var title: String {
        switch self {
        case .disabled: return "Off"
        case .connecting: return "Connecting…"
        case .connected: return "Connected"
        case .fallback: return "Using polling fallback"
        }
    }
    var color: Color {
        switch self {
        case .disabled: return .secondary
        case .connecting: return .orange
        case .connected: return .green
        case .fallback: return .orange
        }
    }
}

private final class DVSStationParser: NSObject, XMLParserDelegate {
    private var insideRitStation = false
    private var readingStationCode = false
    private var value = ""
    private(set) var stationCode: String?

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        let name = elementName.split(separator: ":").last.map(String.init) ?? elementName
        if name == "RitStation" { insideRitStation = true }
        if insideRitStation && name == "StationCode" { readingStationCode = true; value = "" }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if readingStationCode { value += string }
    }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let name = elementName.split(separator: ":").last.map(String.init) ?? elementName
        if readingStationCode && name == "StationCode" {
            let code = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            if !code.isEmpty { stationCode = code; parser.abortParsing() }
            readingStationCode = false
        }
        if name == "RitStation" { insideRitStation = false }
    }
}

private func dvsStationCode(from xml: String) -> String? {
    guard let data = xml.data(using: .utf8) else { return nil }
    let delegate = DVSStationParser()
    let parser = XMLParser(data: data)
    parser.delegate = delegate
    _ = parser.parse()
    return delegate.stationCode
}

private final class NDOVSubscriber {
    enum Event { case connecting, connected, fallback, station(String) }
    private let queue = DispatchQueue(label: "local.nstrainmonitor.ndov", qos: .utility)
    private let lock = NSLock()
    private var stopped = false
    private let handler: (Event) -> Void

    init(handler: @escaping (Event) -> Void) { self.handler = handler }
    func start() { queue.async { [weak self] in self?.run() } }
    func stop() { lock.lock(); stopped = true; lock.unlock() }
    private var shouldStop: Bool { lock.lock(); defer { lock.unlock() }; return stopped }

    private func run() {
        while !shouldStop {
            handler(.connecting)
            guard let client = ndov_client_create() else {
                handler(.fallback); Thread.sleep(forTimeInterval: 5); continue
            }
            var receivedFirstMessage = false
            var lastMessage = Date()
            var buffer = [CChar](repeating: 0, count: 8 * 1024 * 1024)
            while !shouldStop {
                let count = ndov_client_receive(client, &buffer, buffer.count)
                if count > 0 {
                    lastMessage = Date()
                    if !receivedFirstMessage { receivedFirstMessage = true; handler(.connected) }
                    let xml = String(decoding: buffer.prefix(Int(count)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
                    if let station = dvsStationCode(from: xml) { handler(.station(station)) }
                } else if count == -2 {
                    handler(.fallback); break
                } else if Date().timeIntervalSince(lastMessage) > 90 {
                    handler(.fallback); break
                }
            }
            ndov_client_destroy(client)
            if !shouldStop { Thread.sleep(forTimeInterval: 3) }
        }
    }
}

struct Journey: Identifiable, Hashable {
    let id: String, planned: String, actual: String, destination: String, platform: String
    let cancelled: Bool, delay: Int
    var status: String { cancelled ? "Cancelled" : delay > 0 ? "+\(delay) min · expected \(actual)" : "On time" }
    var summary: String { "\(planned) → \(destination) | platform \(platform.isEmpty ? "—" : platform) | \(status)" }
}

enum DepartureCardRenderer {
    static func png(route: String, plan: MonitorPlan, journeys: [Journey], updated: Date) -> Data? {
        let rows = Array(journeys.prefix(5))
        let width = 900, height = 250 + max(1, rows.count) * 92
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                            isPlanar: false, colorSpaceName: .deviceRGB,
                                            bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let canvas = NSRect(x: 0, y: 0, width: width, height: height)
        NSColor(calibratedRed: 0.965, green: 0.975, blue: 0.99, alpha: 1).setFill(); canvas.fill()
        let header = NSRect(x: 0, y: height - 190, width: width, height: 190)
        NSColor(calibratedRed: 0, green: 48/255, blue: 130/255, alpha: 1).setFill(); header.fill()

        func rectFromTop(_ top: CGFloat, _ h: CGFloat, x: CGFloat = 52, w: CGFloat = 796) -> NSRect {
            NSRect(x: x, y: CGFloat(height) - top - h, width: w, height: h)
        }
        func draw(_ text: String, top: CGFloat, height: CGFloat, font: NSFont, color: NSColor,
                  alignment: NSTextAlignment = .left, x: CGFloat = 52, width: CGFloat = 796) {
            let paragraph = NSMutableParagraphStyle(); paragraph.alignment = alignment
            (text as NSString).draw(in: rectFromTop(top, height, x: x, w: width),
                                    withAttributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph])
        }

        draw(route, top: 38, height: 48, font: .systemFont(ofSize: 34, weight: .bold), color: .white)
        draw("Departures \(plan.departureFrom)–\(plan.departureUntil)", top: 100, height: 28,
             font: .systemFont(ofSize: 21, weight: .medium), color: NSColor.white.withAlphaComponent(0.82))
        let formatter = DateFormatter(); formatter.timeZone = TimeZone(identifier: "Europe/Amsterdam"); formatter.dateFormat = "HH:mm"
        draw("Updated \(formatter.string(from: updated))", top: 136, height: 27,
             font: .systemFont(ofSize: 19), color: NSColor.white.withAlphaComponent(0.7))

        if rows.isEmpty {
            draw("No departures returned", top: 235, height: 42, font: .systemFont(ofSize: 25, weight: .semibold), color: .secondaryLabelColor)
        } else {
            for (index, journey) in rows.enumerated() {
                let top = CGFloat(218 + index * 92)
                if index > 0 {
                    NSColor.separatorColor.setFill(); NSRect(x: 52, y: CGFloat(height) - top + 17, width: 796, height: 1).fill()
                }
                draw(journey.planned, top: top, height: 36, font: .monospacedDigitSystemFont(ofSize: 27, weight: .bold), color: .labelColor, width: 110)
                let expected = journey.cancelled ? "Cancelled" : journey.delay > 0 ? "Expected \(journey.actual) · +\(journey.delay) min" : "On time"
                let statusColor: NSColor = journey.cancelled ? .systemRed : journey.delay > 0 ? .systemOrange : .systemGreen
                draw(expected, top: top + 4, height: 30, font: .systemFont(ofSize: 21, weight: .semibold), color: statusColor, x: 180, width: 470)
                draw("Platform \(journey.platform.isEmpty ? "—" : journey.platform)", top: top + 4, height: 30,
                     font: .systemFont(ofSize: 21, weight: .semibold), color: .labelColor, alignment: .right, x: 650, width: 198)
                draw(journey.destination, top: top + 41, height: 26, font: .systemFont(ofSize: 18), color: .secondaryLabelColor, x: 180, width: 668)
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        return bitmap.representation(using: .png, properties: [:])
    }
}

enum Keychain {
    static let service = "local.nstrainmonitor.native"
    static func load() -> String {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
    static func save(_ value: String) {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
        SecItemDelete(q as CFDictionary)
        guard !value.isEmpty else { return }
        var item = q; item[kSecValueData as String] = Data(value.utf8); SecItemAdd(item as CFDictionary, nil)
    }
}

@MainActor final class MonitorModel: ObservableObject {
    @Published var plans: [MonitorPlan] = []
    @Published var stations: [Station] = fallbackStations
    @Published var settings = AppSettings()
    @Published var apiKey = ""
    @Published var journeys: [UUID: [Journey]] = [:]
    @Published var running: Set<UUID> = []
    @Published var working: Set<UUID> = []
    @Published var logs: [String] = []
    @Published var errorMessage: String?
    @Published var testingNotification = false
    @Published var connectionTestMessage: String?
    @Published var ndovState: NDOVConnectionState = .disabled
    private var tasks: [UUID: Task<Void, Never>] = [:]
    private var ndovSubscriber: NDOVSubscriber?
    private var lastLiveRefresh: [String: Date] = [:]
    private let defaults = UserDefaults.standard
    private let amsterdam = TimeZone(identifier: "Europe/Amsterdam")!

    init() {
        apiKey = Keychain.load()
        if let d = defaults.data(forKey: "plans"), let v = try? JSONDecoder().decode([MonitorPlan].self, from: d) { plans = v }
        if let d = defaults.data(forKey: "appSettings"), let v = try? JSONDecoder().decode(AppSettings.self, from: d) { settings = v }
        if let d = defaults.data(forKey: "stations"), let v = try? JSONDecoder().decode([Station].self, from: d), !v.isEmpty { stations = v }
        importLegacyIfNeeded()
        if plans.isEmpty { plans = [MonitorPlan()] }
        Task { await refreshStations() }
    }
    deinit { tasks.values.forEach { $0.cancel() }; ndovSubscriber?.stop() }

    func stationName(_ code: String) -> String { stations.first { $0.code == code }?.name ?? code }
    func saveConnection(_ newSettings: AppSettings, _ newKey: String) {
        settings = newSettings; apiKey = newKey.trimmingCharacters(in: .whitespacesAndNewlines)
        persist(); Keychain.save(apiKey); log("Connection settings saved"); configureNDOV(); Task { await refreshStations() }
    }
    func add(_ p: MonitorPlan) { plans.append(p); persist(); log("Added \(stationName(p.departureCode)) → \(stationName(p.destinationCode))") }
    func update(_ p: MonitorPlan) { if let i = plans.firstIndex(where: { $0.id == p.id }) { plans[i] = p; persist(); log("Updated monitor") } }
    func delete(_ p: MonitorPlan) { stop(p); plans.removeAll { $0.id == p.id }; journeys[p.id] = nil; persist(); log("Removed monitor") }
    func clearActivity() { logs.removeAll() }
    func toggle(_ p: MonitorPlan) { running.contains(p.id) ? stop(p) : start(p) }
    func start(_ p: MonitorPlan) {
        guard configured else { errorMessage = "Add your NS API key and ntfy topic in Connection Settings first."; return }
        guard !running.contains(p.id) else { return }
        running.insert(p.id); log("Started \(stationName(p.departureCode)) → \(stationName(p.destinationCode))")
        configureNDOV()
        tasks[p.id] = Task { [weak self] in
            guard let self else { return }
            if self.inCheckWindow(p) { await self.check(p, alerts: true) }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(max(60, p.pollMinutes * 60)))
                if self.inCheckWindow(p) && (!self.settings.usesLiveNDOV || self.ndovState != .connected) {
                    await self.check(p, alerts: true)
                }
            }
        }
    }
    func stop(_ p: MonitorPlan) { tasks[p.id]?.cancel(); tasks[p.id] = nil; running.remove(p.id); log("Stopped monitor"); configureNDOV() }
    func checkNow(_ p: MonitorPlan) { Task { await check(p, alerts: true) } }
    var configured: Bool { !apiKey.isEmpty && !settings.ntfyTopic.isEmpty }

    private func configureNDOV() {
        guard settings.usesLiveNDOV, !running.isEmpty else {
            ndovSubscriber?.stop(); ndovSubscriber = nil; ndovState = .disabled; return
        }
        guard ndovSubscriber == nil else { return }
        ndovState = .connecting
        let subscriber = NDOVSubscriber { [weak self] event in
            Task { @MainActor [weak self] in self?.handleNDOV(event) }
        }
        ndovSubscriber = subscriber
        subscriber.start()
    }

    private func handleNDOV(_ event: NDOVSubscriber.Event) {
        switch event {
        case .connecting: ndovState = .connecting
        case .connected: ndovState = .connected; log("NDOV live updates connected")
        case .fallback: ndovState = .fallback; log("NDOV unavailable; polling fallback active")
        case .station(let code):
            guard ndovState == .connected else { return }
            let now = Date()
            guard now.timeIntervalSince(lastLiveRefresh[code] ?? .distantPast) >= 5 else { return }
            lastLiveRefresh[code] = now
            for plan in plans where running.contains(plan.id) && plan.departureCode.uppercased() == code && inCheckWindow(plan) {
                Task { await check(plan, alerts: true) }
            }
        }
    }

    func testNotification(topic: String) {
        let candidate = topic.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else { connectionTestMessage = "Enter an ntfy topic first."; return }
        testingNotification = true; connectionTestMessage = nil
        Task {
            defer { testingNotification = false }
            do {
                guard let plan = plans.first,
                      let testCard = DepartureCardRenderer.png(route: "\(stationName(plan.departureCode)) → \(stationName(plan.destinationCode))", plan: plan, journeys: journeys[plan.id] ?? [], updated: Date()) else {
                    throw NSError(domain: "DepartureCard", code: 1,
                                  userInfo: [NSLocalizedDescriptionKey: "The departure card could not be generated."])
                }
                try await notify("NS Train Monitor", "Test from your Mac. Tap to view the departure card.", topic: candidate, card: testCard)
                connectionTestMessage = "Test notification and card sent successfully."
                log("Test notification sent")
            } catch {
                connectionTestMessage = "Test failed: \(error.localizedDescription)"
                log("Test notification failed: \(error.localizedDescription)")
            }
        }
    }

    func refreshStations() async {
        guard !apiKey.isEmpty else { return }
        do {
            var request = URLRequest(url: URL(string: "https://gateway.apiportal.ns.nl/nsapp-stations/v2")!)
            request.setValue(apiKey, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return }
            let root = try JSONSerialization.jsonObject(with: data)
            let rows = root as? [[String: Any]] ?? (root as? [String: Any])?["payload"] as? [[String: Any]] ?? []
            let loaded = rows.compactMap { row -> Station? in
                guard let code = row["code"] as? String else { return nil }
                let names = row["namen"] as? [String: Any]
                let name = names?["lang"] as? String ?? names?["middel"] as? String ?? row["name"] as? String ?? code
                return Station(code: code.uppercased(), name: name)
            }.filter { !$0.name.isEmpty }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            if !loaded.isEmpty { stations = loaded; if let d = try? JSONEncoder().encode(loaded) { defaults.set(d, forKey: "stations") }; log("Station list updated") }
        } catch { log("Could not update station list; using cached list") }
    }

    private func check(_ p: MonitorPlan, alerts: Bool) async {
        guard configured, !working.contains(p.id) else { if !configured { errorMessage = "Connection settings are incomplete." }; return }
        working.insert(p.id); defer { working.remove(p.id) }
        do { let found = try await fetchJourneys(p); journeys[p.id] = found; log("Checked \(stationName(p.departureCode)) → \(stationName(p.destinationCode)): \(found.count) journeys"); if alerts { try await processAlerts(p, found) } }
        catch { errorMessage = error.localizedDescription; log("Check failed: \(error.localizedDescription)") }
    }

    private func fetchJourneys(_ p: MonitorPlan) async throws -> [Journey] {
        var c = URLComponents(string: "https://gateway.apiportal.ns.nl/reisinformatie-api/api/v3/trips")!
        c.queryItems = [URLQueryItem(name: "fromStation", value: p.departureCode), URLQueryItem(name: "toStation", value: p.destinationCode),
                        URLQueryItem(name: "dateTime", value: apiDateTime(p.departureFrom)), URLQueryItem(name: "searchForArrival", value: "false"),
                        URLQueryItem(name: "lang", value: "en")]
        var r = URLRequest(url: c.url!); r.timeoutInterval = 25; r.setValue(apiKey, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")
        let (data, response) = try await URLSession.shared.data(for: r)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw NSError(domain: "NS", code: -1, userInfo: [NSLocalizedDescriptionKey: "NS could not return journeys. Check the route and API access."]) }
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let trips = root?["trips"] as? [[String: Any]] ?? []
        let iso = ISO8601DateFormatter()
        let mapped = trips.compactMap { trip -> Journey? in
            guard let legs = trip["legs"] as? [[String: Any]], let first = legs.first, let last = legs.last else { return nil }
            let origin = first["origin"] as? [String: Any] ?? [:], destination = last["destination"] as? [String: Any] ?? [:]
            guard let raw = origin["plannedDateTime"] as? String, let plannedDate = iso.date(from: raw) else { return nil }
            let planned = timeString(plannedDate)
            guard clock(planned) >= clock(p.departureFrom), clock(planned) < clock(p.departureUntil) else { return nil }
            let actual = (origin["actualDateTime"] as? String).flatMap(iso.date(from:)) ?? plannedDate
            let product = first["product"] as? [String: Any]
            let trainNumber = product?["number"] as? String ?? ""
            let serviceID = "\(p.id):\(raw):\(trainNumber)"
            return Journey(id: serviceID, planned: planned, actual: timeString(actual),
                           destination: destination["name"] as? String ?? stationName(p.destinationCode),
                           platform: origin["actualTrack"] as? String ?? origin["plannedTrack"] as? String ?? "",
                           cancelled: legs.contains { $0["cancelled"] as? Bool == true }, delay: max(0, Int((actual.timeIntervalSince(plannedDate) / 60).rounded())))
        }
        var seenServices = Set<String>()
        return mapped.filter { seenServices.insert($0.id).inserted }.prefix(p.maximumDepartures).map { $0 }
    }

    private func processAlerts(_ p: MonitorPlan, _ found: [Journey]) async throws {
        let dayKey = "day-\(p.id)", summaryKey = "summary-\(p.id)", statusesKey = "statuses-\(p.id)", day = dateString(Date())
        if defaults.string(forKey: dayKey) != day { defaults.set(day, forKey: dayKey); defaults.set(false, forKey: summaryKey); defaults.removeObject(forKey: statusesKey) }
        var statuses = defaults.dictionary(forKey: statusesKey) as? [String: String] ?? [:]
        let route = "\(stationName(p.departureCode)) → \(stationName(p.destinationCode))"
        let card = DepartureCardRenderer.png(route: route, plan: p, journeys: found, updated: Date())
        if card == nil { log("Card generation failed; sending text fallback") }
        if !defaults.bool(forKey: summaryKey) {
            let message = found.isEmpty ? "No departures returned for \(p.departureFrom)–\(p.departureUntil). Tap to view the card." : "\(found.count) departure\(found.count == 1 ? "" : "s") for \(p.departureFrom)–\(p.departureUntil). Tap to view the card."
            try await notify(route, message, card: card); defaults.set(true, forKey: summaryKey)
        } else {
            for j in found where statuses[j.id] != nil && statuses[j.id] != j.summary {
                let platform = j.platform.isEmpty ? "platform unknown" : "platform \(j.platform)"
                try await notify(j.cancelled ? "Journey cancelled" : "Journey changed", "\(j.planned) · \(j.status) · \(platform). Tap to view all departures.", card: card)
            }
        }
        found.forEach { statuses[$0.id] = $0.summary }; defaults.set(statuses, forKey: statusesKey)
    }
    private func notify(_ title: String, _ message: String, topic override: String? = nil, card: Data? = nil) async throws {
        let rawTopic = override ?? settings.ntfyTopic
        let topic = rawTopic.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? rawTopic
        let url = URL(string: "https://ntfy.sh/\(topic)")!
        if let card {
            do {
                var upload = URLRequest(url: url); upload.httpMethod = "PUT"; upload.httpBody = card
                upload.setValue(ntfyHeader(title), forHTTPHeaderField: "Title"); upload.setValue(ntfyHeader(message), forHTTPHeaderField: "Message")
                upload.setValue("departure-card.png", forHTTPHeaderField: "Filename"); upload.setValue("3", forHTTPHeaderField: "Priority")
                upload.setValue("image/png", forHTTPHeaderField: "Content-Type")
                let (data, response) = try await URLSession.shared.data(for: upload)
                try validateNotificationResponse(data, response)
                return
            } catch {
                log("Card attachment failed; sending text fallback")
            }
        }
        var r = URLRequest(url: url); r.httpMethod = "POST"; r.httpBody = Data(message.utf8); r.setValue(ntfyHeader(title), forHTTPHeaderField: "Title"); r.setValue("3", forHTTPHeaderField: "Priority"); r.setValue("text/plain; charset=utf-8", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await URLSession.shared.data(for: r)
        try validateNotificationResponse(data, response)
    }
    private func validateNotificationResponse(_ data: Data, _ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let detail = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw NSError(domain: "ntfy", code: (response as? HTTPURLResponse)?.statusCode ?? -1,
                          userInfo: [NSLocalizedDescriptionKey: detail?.isEmpty == false ? detail! : "Notification service rejected the request."])
        }
    }
    private func ntfyHeader(_ value: String) -> String {
        guard !value.unicodeScalars.allSatisfy({ $0.value < 128 }) else { return value }
        return "=?UTF-8?B?\(Data(value.utf8).base64EncodedString())?="
    }

    private func persist() { if let d = try? JSONEncoder().encode(plans) { defaults.set(d, forKey: "plans") }; if let d = try? JSONEncoder().encode(settings) { defaults.set(d, forKey: "appSettings") } }
    private func importLegacyIfNeeded() {
        guard defaults.data(forKey: "plans") == nil else { return }
        let file = URL(fileURLWithPath: Bundle.main.bundlePath).deletingLastPathComponent().appendingPathComponent("config.json")
        guard let data = try? Data(contentsOf: file), let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        let legacyName = j["StationName"] as? String ?? ""
        let code = legacyName.localizedCaseInsensitiveContains("Anna Paulowna") ? "ANA" : (j["Station"] as? String ?? "ANA").uppercased()
        plans = [MonitorPlan(departureCode: code, destinationCode: code == "ASD" ? "UT" : "ASD", departureFrom: j["From"] as? String ?? "07:00", departureUntil: j["Until"] as? String ?? "08:00", firstCheck: j["FirstCheck"] as? String ?? "06:30", lastCheck: j["LastCheck"] as? String ?? "08:00", pollMinutes: j["PollMinutes"] as? Int ?? 5, maximumDepartures: 5)]
        settings.ntfyTopic = j["NtfyTopic"] as? String ?? ""
        if let key = j["NsApiKey"] as? String, !key.hasPrefix("REPLACE_") { Keychain.save(key); apiKey = key }
        persist()
    }
    private func log(_ s: String) { logs.insert("\(Date.now.formatted(date: .omitted, time: .shortened))  \(s)", at: 0); if logs.count > 150 { logs.removeLast() } }
    private func clock(_ s: String) -> Int { let p = s.split(separator: ":").compactMap { Int($0) }; return p.count == 2 ? p[0] * 60 + p[1] : 0 }
    private func inCheckWindow(_ p: MonitorPlan) -> Bool {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = amsterdam
        guard p.activeDays.contains(calendar.component(.weekday, from: Date())) else { return false }
        let n = timeString(Date())
        return clock(n) >= clock(p.firstCheck) && clock(n) <= clock(p.lastCheck)
    }
    private func timeString(_ d: Date) -> String { let f = DateFormatter(); f.timeZone = amsterdam; f.dateFormat = "HH:mm"; return f.string(from: d) }
    private func dateString(_ d: Date) -> String { let f = DateFormatter(); f.timeZone = amsterdam; f.dateFormat = "yyyy-MM-dd"; return f.string(from: d) }
    private func apiDateTime(_ t: String) -> String { let f = ISO8601DateFormatter(); var cal = Calendar(identifier: .gregorian); cal.timeZone = amsterdam; let p = t.split(separator: ":").compactMap { Int($0) }; let d = cal.date(bySettingHour: p.first ?? 0, minute: p.count > 1 ? p[1] : 0, second: 0, of: Date()) ?? Date(); return f.string(from: d) }

    static let fallbackStations: [Station] = [("ANA","Anna Paulowna"),("ASD","Amsterdam Centraal"),("ASB","Amsterdam Bijlmer ArenA"),("ASS","Amsterdam Zuid"),("AMF","Amersfoort Centraal"),("AH","Arnhem Centraal"),("ALM","Almere Centrum"),("APD","Apeldoorn"),("BRD","Breda"),("DT","Delft"),("DV","Deventer"),("EHV","Eindhoven Centraal"),("ES","Enschede"),("GVC","Den Haag Centraal"),("GD","Gouda"),("GN","Groningen"),("HLM","Haarlem"),("HFD","Hoofddorp"),("HORN","Hoorn"),("LC","Leeuwarden"),("LEID","Leiden Centraal"),("MAS","Maastricht"),("NML","Nijmegen"),("RTA","Rotterdam Centraal"),("SHL","Schiphol Airport"),("HT","'s-Hertogenbosch"),("TB","Tilburg"),("UT","Utrecht Centraal"),("ZL","Zwolle")].map { Station(code: $0.0, name: $0.1) }.sorted { $0.name < $1.name }
}

enum AppSection: String, CaseIterable, Identifiable {
    case monitors = "Monitors", activity = "Recent Activity", connections = "Connections"
    var id: String { rawValue }
    var icon: String { switch self { case .monitors: "tram.fill"; case .activity: "clock.arrow.circlepath"; case .connections: "network" } }
}

struct RootView: View {
    @ObservedObject var model: MonitorModel
    @State private var editingPlan: MonitorPlan?
    @State private var selection: AppSection? = .monitors
    var body: some View {
        NavigationSplitView {
            List(AppSection.allCases, selection: $selection) { item in Label(item.rawValue, systemImage: item.icon).tag(item) }
                .navigationTitle("NS Monitor")
        } detail: {
            switch selection ?? .monitors {
            case .monitors: OverviewView(model: model, edit: { editingPlan = $0 }, add: { addMonitor() })
            case .activity: ActivityView(model: model)
            case .connections: ConnectionsView(model: model)
            }
        }
        .tint(Color(red: 0, green: 48/255, blue: 130/255)).frame(minWidth: 900, minHeight: 600)
        .sheet(item: $editingPlan) { p in PlanEditor(model: model, original: model.plans.contains(where: { $0.id == p.id }) ? p : nil, draft: p) }
        .alert("NS Train Monitor", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) { Button("OK") { model.errorMessage = nil } } message: { Text(model.errorMessage ?? "") }
    }
    private func addMonitor() { editingPlan = MonitorPlan(departureCode: model.stations.first?.code ?? "ANA", destinationCode: model.stations.dropFirst().first?.code ?? "ASD") }
}

struct MonitorSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .fontWeight(.medium)
            .foregroundStyle(Color.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Color.primary.opacity(configuration.isPressed ? 0.20 : 0.12), in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.primary.opacity(0.18), lineWidth: 1))
            .opacity(isEnabled ? 1 : 0.45)
    }
}

struct OverviewView: View {
    @ObservedObject var model: MonitorModel; let edit: (MonitorPlan) -> Void; let add: () -> Void
    private func liveLabel(for plan: MonitorPlan) -> (String, Color) {
        guard model.running.contains(plan.id) else { return ("NDOV enabled", .blue) }
        switch model.ndovState {
        case .connected: return ("NDOV live", .green)
        case .connecting: return ("NDOV connecting", .orange)
        case .fallback: return ("Polling fallback", .orange)
        case .disabled: return ("NDOV enabled", .blue)
        }
    }
    var body: some View { ScrollView { LazyVStack(spacing: 16) {
        HStack { VStack(alignment: .leading) { Text("Monitors").font(.largeTitle.bold()); Text("Each route runs on its own schedule.").foregroundStyle(.secondary) }; Spacer(); Button(action: add) { Label("Add monitor", systemImage: "plus") }.buttonStyle(.borderedProminent) }.padding(.bottom, 8)
        ForEach(model.plans) { p in VStack(alignment: .leading, spacing: 14) {
            HStack { VStack(alignment: .leading, spacing: 5) {
                Text("\(model.stationName(p.departureCode)) → \(model.stationName(p.destinationCode))").font(.title2.bold())
                HStack(spacing: 8) {
                    Text(model.settings.usesLiveNDOV
                         ? "Departures \(p.departureFrom)–\(p.departureUntil) · \(p.daysLabel) · checks \(p.firstCheck)–\(p.lastCheck) · fallback every \(p.pollMinutes) min"
                         : "Departures \(p.departureFrom)–\(p.departureUntil) · \(p.daysLabel) · checks \(p.firstCheck)–\(p.lastCheck) every \(p.pollMinutes) min")
                        .foregroundStyle(.secondary)
                    if model.settings.usesLiveNDOV {
                        let badge = liveLabel(for: p)
                        Label(badge.0, systemImage: badge.0 == "NDOV live" ? "bolt.horizontal.circle.fill" : "antenna.radiowaves.left.and.right")
                            .font(.caption.weight(.semibold)).foregroundStyle(badge.1)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(badge.1.opacity(0.14), in: Capsule())
                    }
                }
            }; Spacer(); Circle().fill(model.running.contains(p.id) ? .green : .gray.opacity(0.4)).frame(width: 10, height: 10) }
            HStack {
                Button(model.running.contains(p.id) ? "Stop" : "Start") { model.toggle(p) }.buttonStyle(.borderedProminent)
                Button("Check now") { model.checkNow(p) }.buttonStyle(MonitorSecondaryButtonStyle()).disabled(model.working.contains(p.id))
                Button("Edit") { edit(p) }.buttonStyle(MonitorSecondaryButtonStyle())
                Spacer(); if model.working.contains(p.id) { ProgressView().controlSize(.small) }
            }
            if let rows = model.journeys[p.id], !rows.isEmpty { Divider(); ForEach(rows) { j in HStack { Text(j.planned).font(.headline.monospacedDigit()).frame(width: 55, alignment: .leading); VStack(alignment: .leading) { Text(j.destination); Text(j.status).font(.caption).foregroundStyle(j.cancelled ? .red : j.delay > 0 ? .orange : .secondary) }; Spacer(); Text(j.platform.isEmpty ? "—" : j.platform).bold() } } }
        }.padding(20).background(.background, in: RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(.quaternary)) }
        if model.plans.isEmpty { ContentUnavailableView("No monitors", systemImage: "tram", description: Text("Use + to add a route.")) }
    }.padding(28) }.background(Color(nsColor: .windowBackgroundColor)) }
}

struct ActivityView: View {
    @ObservedObject var model: MonitorModel
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Recent Activity").font(.largeTitle.bold())
                Spacer()
                Button("Clear") { model.clearActivity() }
                    .buttonStyle(MonitorSecondaryButtonStyle())
                    .disabled(model.logs.isEmpty)
            }.padding(28)
            Divider()
            if model.logs.isEmpty { ContentUnavailableView("No recent activity", systemImage: "clock", description: Text("Monitor checks and changes will appear here.")) }
            else { List(model.logs, id: \.self) { Text($0).font(.system(.body, design: .monospaced)).textSelection(.enabled).padding(.vertical, 3) }.listStyle(.inset) }
        }
    }
}

struct PlanEditor: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: MonitorModel; let original: MonitorPlan?; @State var draft: MonitorPlan
    private var changed: Bool { original == nil || original != draft }
    private var valid: Bool { draft.departureCode != draft.destinationCode && draft.departureFrom < draft.departureUntil && draft.firstCheck < draft.lastCheck && !draft.activeDays.isEmpty }
    var body: some View { VStack(spacing: 0) {
        HStack { Text(original == nil ? "New monitor" : "Edit monitor").font(.title2.bold()); Spacer(); Button("Cancel") { dismiss() }; Button("Save") { original == nil ? model.add(draft) : model.update(draft); dismiss() }.buttonStyle(.borderedProminent).disabled(!changed || !valid) }.padding()
        Form { Section("Journey") {
                LabeledContent("Departure") { StationComboBox(stations: model.stations, selection: $draft.departureCode).frame(width: 300, height: 26) }
                LabeledContent("Destination") { StationComboBox(stations: model.stations, selection: $draft.destinationCode).frame(width: 300, height: 26) }
                Text("Type any part of a station name, such as “Amsterdam”, to filter the list.").font(.caption).foregroundStyle(.secondary)
                if draft.departureCode == draft.destinationCode { Text("Departure and destination must be different.").foregroundStyle(.red) }
            }
            Section("Departure times") { TimePicker(title: "From", value: $draft.departureFrom); TimePicker(title: "Until", value: $draft.departureUntil); Stepper("Maximum departures: \(draft.maximumDepartures)", value: $draft.maximumDepartures, in: 1...50) }
            Section("Monitoring schedule") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Days").font(.headline)
                    HStack(spacing: 7) {
                        ForEach([(2, "Mon"), (3, "Tue"), (4, "Wed"), (5, "Thu"), (6, "Fri"), (7, "Sat"), (1, "Sun")], id: \.0) { day, label in
                            DayToggle(label: label, selected: draft.activeDays.contains(day)) {
                                var selected = draft.activeDays
                                if selected.contains(day) { selected.remove(day) } else { selected.insert(day) }
                                draft.monitoringDays = selected
                            }
                        }
                    }
                    if draft.activeDays.isEmpty { Text("Select at least one monitoring day.").font(.caption).foregroundStyle(.red) }
                }.padding(.vertical, 4)
                TimePicker(title: "First check", value: $draft.firstCheck)
                TimePicker(title: "Last check", value: $draft.lastCheck)
                Stepper("Check every \(draft.pollMinutes) minutes", value: $draft.pollMinutes, in: 1...60)
            }
            if let original { Section { Button("Delete monitor", role: .destructive) { model.delete(original); dismiss() } } }
        }.formStyle(.grouped).padding()
    }.frame(width: 560, height: 560) }
}

struct DayToggle: View {
    let label: String, selected: Bool, action: () -> Void
    var body: some View {
        Button(action: action) { Text(label).font(.callout.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 7) }
            .buttonStyle(.plain)
            .foregroundStyle(selected ? Color.white : Color.primary)
            .background(selected ? Color.accentColor : Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected ? Color.accentColor : Color.secondary.opacity(0.35), lineWidth: 1))
            .accessibilityLabel(label)
            .accessibilityValue(selected ? "Selected" : "Not selected")
    }
}

struct StationComboBox: NSViewRepresentable {
    let stations: [Station]
    @Binding var selection: String
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSComboBox {
        let box = NSComboBox(); box.isEditable = true; box.completes = false; box.numberOfVisibleItems = 12
        box.delegate = context.coordinator; context.coordinator.box = box
        context.coordinator.showAll(in: box)
        box.stringValue = stations.first(where: { $0.code == selection })?.name ?? selection
        return box
    }
    func updateNSView(_ box: NSComboBox, context: Context) {
        context.coordinator.parent = self
        if !context.coordinator.isTyping { box.stringValue = stations.first(where: { $0.code == selection })?.name ?? selection }
    }
    final class Coordinator: NSObject, NSComboBoxDelegate {
        var parent: StationComboBox; weak var box: NSComboBox?; var filtered: [Station] = []; var isTyping = false
        init(_ parent: StationComboBox) { self.parent = parent }
        func showAll(in box: NSComboBox) { filtered = parent.stations; box.removeAllItems(); box.addItems(withObjectValues: filtered.map(\.name)) }
        func controlTextDidBeginEditing(_ notification: Notification) { isTyping = true }
        func controlTextDidChange(_ notification: Notification) {
            guard let box else { return }; let query = box.stringValue
            filtered = query.isEmpty ? parent.stations : parent.stations.filter { $0.name.localizedCaseInsensitiveContains(query) }
            box.removeAllItems(); box.addItems(withObjectValues: filtered.map(\.name))
            if !query.isEmpty && !filtered.isEmpty { box.performClick(nil) }
            if let exact = parent.stations.first(where: { $0.name.localizedCaseInsensitiveCompare(query) == .orderedSame }) { parent.selection = exact.code }
        }
        func comboBoxSelectionDidChange(_ notification: Notification) {
            guard let box, box.indexOfSelectedItem >= 0, box.indexOfSelectedItem < filtered.count else { return }
            let station = filtered[box.indexOfSelectedItem]; parent.selection = station.code; box.stringValue = station.name
        }
        func controlTextDidEndEditing(_ notification: Notification) {
            isTyping = false
            guard let box else { return }
            if let match = parent.stations.first(where: { $0.name.localizedCaseInsensitiveCompare(box.stringValue) == .orderedSame }) { parent.selection = match.code }
            box.stringValue = parent.stations.first(where: { $0.code == parent.selection })?.name ?? parent.selection
        }
    }
}

struct TimePicker: View {
    let title: String; @Binding var value: String
    var date: Binding<Date> { Binding(get: { Self.parser.date(from: value) ?? Date() }, set: { value = Self.parser.string(from: $0) }) }
    var body: some View { DatePicker(title, selection: date, displayedComponents: .hourAndMinute).datePickerStyle(.field) }
    static let parser: DateFormatter = { let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "HH:mm"; return f }()
}

struct ConnectionsView: View {
    @ObservedObject var model: MonitorModel
    @State private var topic: String; @State private var key: String; @State private var liveNDOV: Bool
    init(model: MonitorModel) {
        self.model = model
        _topic = State(initialValue: model.settings.ntfyTopic)
        _key = State(initialValue: model.apiKey)
        _liveNDOV = State(initialValue: model.settings.usesLiveNDOV)
    }
    var body: some View { VStack(spacing: 0) {
        HStack { VStack(alignment: .leading) { Text("Connections").font(.largeTitle.bold()); Text("NS journey data, live updates and phone notifications").foregroundStyle(.secondary) }; Spacer(); Button("Save") { model.saveConnection(AppSettings(ntfyTopic: topic, liveNDOVEnabled: liveNDOV), key) }.buttonStyle(.borderedProminent).disabled(topic == model.settings.ntfyTopic && key == model.apiKey && liveNDOV == model.settings.usesLiveNDOV) }.padding(28)
        Form {
            Section("NS API") { SecureField("Subscription key", text: $key); Text("Stored securely in macOS Keychain.").font(.caption).foregroundStyle(.secondary) }
            Section("Live departure updates") {
                Toggle("Use NDOV live updates (experimental)", isOn: $liveNDOV)
                HStack(spacing: 8) {
                    Circle().fill(model.ndovState.color).frame(width: 8, height: 8)
                    Text(liveNDOV ? model.ndovState.title : "Off")
                }
                .font(.caption)
                Text("When enabled, live station events trigger a fresh NS journey check. Your check interval is kept as an automatic fallback if the live feed disconnects.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Notifications") {
                TextField("ntfy topic", text: $topic)
                HStack {
                    Button("Send test notification + card") { model.testNotification(topic: topic) }.disabled(topic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.testingNotification)
                    if model.testingNotification { ProgressView().controlSize(.small) }
                }
                if let result = model.connectionTestMessage {
                    Text(result).font(.caption).foregroundStyle(result.hasPrefix("Test failed") ? .red : .green)
                }
                Text("Test always sends. Daily summaries are sent once per monitor; later checks notify only when a journey changes.").font(.caption).foregroundStyle(.secondary)
            }
            Section { Button("Refresh station list") { model.saveConnection(AppSettings(ntfyTopic: topic, liveNDOVEnabled: liveNDOV), key) }.disabled(key.isEmpty) }
        }.formStyle(.grouped).padding().frame(maxWidth: 650)
        Spacer()
    }.onAppear { topic = model.settings.ntfyTopic; key = model.apiKey; liveNDOV = model.settings.usesLiveNDOV } }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var closeObserver: NSObjectProtocol?
    private func installApplicationIcon() {
        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = icon
        }
    }
    func applicationWillFinishLaunching(_ notification: Notification) {
        installApplicationIcon()
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        installApplicationIcon()
        closeObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { notification in
            guard let closingWindow = notification.object as? NSWindow, !(closingWindow is NSPanel) else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                let hasAnotherMainWindow = NSApp.windows.contains {
                    $0 !== closingWindow && $0.isVisible && $0.canBecomeKey && !($0 is NSPanel)
                }
                if !hasAnotherMainWindow {
                    NSApp.setActivationPolicy(.accessory)
                }
            }
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    deinit { if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) } }
}

struct MenuBarMenu: View {
    @ObservedObject var model: MonitorModel
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("Open NS Train Monitor") {
            NSApp.setActivationPolicy(.regular)
            if let window = NSApp.windows.first(where: {
                ($0.isVisible || $0.isMiniaturized) && $0.canBecomeKey && !($0 is NSPanel)
            }) {
                if window.isMiniaturized { window.deminiaturize(nil) }
                window.makeKeyAndOrderFront(nil)
            } else {
                openWindow(id: "main")
            }
            NSApp.activate(ignoringOtherApps: true)
        }
        Divider()
        Text(model.running.isEmpty ? "No active monitors" : "\(model.running.count) active monitor\(model.running.count == 1 ? "" : "s")")
        Divider()
        Button("Quit NS Train Monitor") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

@main struct NSTrainMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = MonitorModel()
    var body: some Scene {
        WindowGroup(id: "main") { RootView(model: model) }
            .windowStyle(.titleBar)
            .commands { CommandGroup(replacing: .newItem) { } }
        MenuBarExtra("NS Train Monitor", systemImage: "tram.fill") {
            MenuBarMenu(model: model)
        }
    }
}
