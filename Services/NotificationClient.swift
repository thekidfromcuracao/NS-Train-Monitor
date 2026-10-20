import Foundation

struct NotificationClient {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func send(_ title: String, _ message: String, topic rawTopic: String, card: Data? = nil,
              attachmentFailed: () -> Void) async throws {
        let topic = rawTopic.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? rawTopic
        guard let url = URL(string: "https://ntfy.sh/\(topic)") else {
            throw URLError(.badURL)
        }
        if let card {
            do {
                var upload = URLRequest(url: url); upload.httpMethod = "PUT"; upload.httpBody = card
                upload.setValue(ntfyHeader(title), forHTTPHeaderField: "Title"); upload.setValue(ntfyHeader(message), forHTTPHeaderField: "Message")
                upload.setValue("departure-card.png", forHTTPHeaderField: "Filename"); upload.setValue("3", forHTTPHeaderField: "Priority")
                upload.setValue("image/png", forHTTPHeaderField: "Content-Type")
                let (data, response) = try await session.data(for: upload)
                try validateNotificationResponse(data, response)
                return
            } catch {
                attachmentFailed()
            }
        }
        var r = URLRequest(url: url); r.httpMethod = "POST"; r.httpBody = Data(message.utf8); r.setValue(ntfyHeader(title), forHTTPHeaderField: "Title"); r.setValue("3", forHTTPHeaderField: "Priority"); r.setValue("text/plain; charset=utf-8", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await session.data(for: r)
        try validateNotificationResponse(data, response)
    }
    private func validateNotificationResponse(_ data: Data, _ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let detail = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw NSError(domain: "ntfy", code: (response as? HTTPURLResponse)?.statusCode ?? -1,
                          userInfo: [NSLocalizedDescriptionKey: detail.flatMap { $0.isEmpty ? nil : $0 } ?? "Notification service rejected the request."])
        }
    }
    private func ntfyHeader(_ value: String) -> String {
        guard !value.unicodeScalars.allSatisfy({ $0.value < 128 }) else { return value }
        return "=?UTF-8?B?\(Data(value.utf8).base64EncodedString())?="
    }

}
