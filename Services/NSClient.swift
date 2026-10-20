import Foundation

struct NSClient {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func stations(apiKey: String) async throws -> [Station] {
        guard let url = URL(string: "https://gateway.apiportal.ns.nl/nsapp-stations/v2") else {
            throw URLError(.badURL)
        }
        let request = authorizedRequest(url: url, apiKey: apiKey)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return [] }
        let root = try JSONSerialization.jsonObject(with: data)
        let rows = root as? [[String: Any]] ?? (root as? [String: Any])?["payload"] as? [[String: Any]] ?? []
        let loaded = rows.compactMap { row -> Station? in
            guard let code = row["code"] as? String else { return nil }
            let names = row["namen"] as? [String: Any]
            let name = names?["lang"] as? String ?? names?["middel"] as? String ?? row["name"] as? String ?? code
            return Station(code: code.uppercased(), name: name)
        }.filter { !$0.name.isEmpty }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return loaded
    }

    func journeys(for p: MonitorPlan, apiKey: String, destinationName: String) async throws -> [Journey] {
        guard var c = URLComponents(string: "https://gateway.apiportal.ns.nl/reisinformatie-api/api/v3/trips") else {
            throw URLError(.badURL)
        }
        c.queryItems = [URLQueryItem(name: "fromStation", value: p.departureCode), URLQueryItem(name: "toStation", value: p.destinationCode),
                        URLQueryItem(name: "dateTime", value: MonitorTime.apiDateTime(p.departureFrom)), URLQueryItem(name: "searchForArrival", value: "false"),
                        URLQueryItem(name: "lang", value: "en")]
        guard let url = c.url else { throw URLError(.badURL) }
        var request = authorizedRequest(url: url, apiKey: apiKey)
        request.timeoutInterval = 25
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw NSError(domain: "NS", code: -1, userInfo: [NSLocalizedDescriptionKey: "NS could not return journeys. Check the route and API access."]) }
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let trips = root?["trips"] as? [[String: Any]] ?? []
        let iso = ISO8601DateFormatter()
        let mapped = trips.compactMap { trip -> Journey? in
            guard let legs = trip["legs"] as? [[String: Any]], let first = legs.first, let last = legs.last else { return nil }
            let origin = first["origin"] as? [String: Any] ?? [:], destination = last["destination"] as? [String: Any] ?? [:]
            guard let raw = origin["plannedDateTime"] as? String, let plannedDate = iso.date(from: raw) else { return nil }
            let planned = MonitorTime.timeString(plannedDate)
            guard MonitorTime.clock(planned) >= MonitorTime.clock(p.departureFrom), MonitorTime.clock(planned) < MonitorTime.clock(p.departureUntil) else { return nil }
            let actual = (origin["actualDateTime"] as? String).flatMap(iso.date(from:)) ?? plannedDate
            let product = first["product"] as? [String: Any]
            let trainNumber = product?["number"] as? String ?? ""
            let serviceID = "\(p.id):\(raw):\(trainNumber)"
            return Journey(id: serviceID, planned: planned, actual: MonitorTime.timeString(actual),
                           destination: destination["name"] as? String ?? destinationName,
                           platform: origin["actualTrack"] as? String ?? origin["plannedTrack"] as? String ?? "",
                           cancelled: legs.contains { $0["cancelled"] as? Bool == true }, delay: max(0, Int((actual.timeIntervalSince(plannedDate) / 60).rounded())))
        }
        var seenServices = Set<String>()
        return Array(mapped.filter { seenServices.insert($0.id).inserted }.prefix(p.maximumDepartures))
    }

    private func authorizedRequest(url: URL, apiKey: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")
        return request
    }
}
