import SwiftUI
import Foundation

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
    private let nsClient: NSClient
    private let notificationClient: NotificationClient

    init(nsClient: NSClient = NSClient(), notificationClient: NotificationClient = NotificationClient()) {
        self.nsClient = nsClient
        self.notificationClient = notificationClient
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
            if MonitorTime.inCheckWindow(p) { await self.check(p) }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(max(60, p.pollMinutes * 60)))
                if MonitorTime.inCheckWindow(p) && (!self.settings.usesLiveNDOV || self.ndovState != .connected) {
                    await self.check(p)
                }
            }
        }
    }
    func stop(_ p: MonitorPlan) { tasks[p.id]?.cancel(); tasks[p.id] = nil; running.remove(p.id); log("Stopped monitor"); configureNDOV() }
    func checkNow(_ p: MonitorPlan) { Task { await check(p) } }
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
            for plan in plans where running.contains(plan.id) && plan.departureCode.uppercased() == code && MonitorTime.inCheckWindow(plan) {
                Task { await check(plan) }
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
            let loaded = try await nsClient.stations(apiKey: apiKey)
            guard !loaded.isEmpty else { return }
            stations = loaded
            if let data = try? JSONEncoder().encode(loaded) {
                defaults.set(data, forKey: "stations")
            }
            log("Station list updated")
        } catch {
            log("Could not update station list; using cached list")
        }
    }

    private func check(_ p: MonitorPlan) async {
        guard configured, !working.contains(p.id) else { if !configured { errorMessage = "Connection settings are incomplete." }; return }
        working.insert(p.id); defer { working.remove(p.id) }
        do { let found = try await nsClient.journeys(for: p, apiKey: apiKey, destinationName: stationName(p.destinationCode)); journeys[p.id] = found; log("Checked \(stationName(p.departureCode)) → \(stationName(p.destinationCode)): \(found.count) journeys"); try await processAlerts(p, found) }
        catch { errorMessage = error.localizedDescription; log("Check failed: \(error.localizedDescription)") }
    }

    private func processAlerts(_ p: MonitorPlan, _ found: [Journey]) async throws {
        let dayKey = "day-\(p.id)", summaryKey = "summary-\(p.id)", statusesKey = "statuses-\(p.id)", day = MonitorTime.dateString(Date())
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
    private func notify(_ title: String, _ message: String, topic: String? = nil, card: Data? = nil) async throws {
        try await notificationClient.send(title, message, topic: topic ?? settings.ntfyTopic, card: card) {
            log("Card attachment failed; sending text fallback")
        }
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
    static let fallbackStations: [Station] = [("ANA","Anna Paulowna"),("ASD","Amsterdam Centraal"),("ASB","Amsterdam Bijlmer ArenA"),("ASS","Amsterdam Zuid"),("AMF","Amersfoort Centraal"),("AH","Arnhem Centraal"),("ALM","Almere Centrum"),("APD","Apeldoorn"),("BRD","Breda"),("DT","Delft"),("DV","Deventer"),("EHV","Eindhoven Centraal"),("ES","Enschede"),("GVC","Den Haag Centraal"),("GD","Gouda"),("GN","Groningen"),("HLM","Haarlem"),("HFD","Hoofddorp"),("HORN","Hoorn"),("LC","Leeuwarden"),("LEID","Leiden Centraal"),("MAS","Maastricht"),("NML","Nijmegen"),("RTA","Rotterdam Centraal"),("SHL","Schiphol Airport"),("HT","'s-Hertogenbosch"),("TB","Tilburg"),("UT","Utrecht Centraal"),("ZL","Zwolle")].map { Station(code: $0.0, name: $0.1) }.sorted { $0.name < $1.name }
}
