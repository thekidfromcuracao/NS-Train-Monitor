import Foundation
import SwiftUI
import CNDOV

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

final class NDOVSubscriber {
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
