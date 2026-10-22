import AppKit

enum DepartureCardRenderer {
    static func png(route: String, plan: MonitorPlan, journeys: [Journey], updated: Date) -> Data? {
        // Exported cards always have a light background, regardless of the app appearance.
        let textColor = NSColor(calibratedWhite: 0.12, alpha: 1)
        let secondaryTextColor = NSColor(calibratedWhite: 0.36, alpha: 1)
        let separatorColor = NSColor(calibratedWhite: 0.82, alpha: 1)
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
            draw("No departures returned", top: 235, height: 42, font: .systemFont(ofSize: 25, weight: .semibold), color: secondaryTextColor)
        } else {
            for (index, journey) in rows.enumerated() {
                let top = CGFloat(218 + index * 92)
                if index > 0 {
                    separatorColor.setFill(); NSRect(x: 52, y: CGFloat(height) - top + 17, width: 796, height: 1).fill()
                }
                draw(journey.planned, top: top, height: 36, font: .monospacedDigitSystemFont(ofSize: 27, weight: .bold), color: textColor, width: 110)
                let expected = journey.cancelled ? "Cancelled" : journey.delay > 0 ? "Expected \(journey.actual) · +\(journey.delay) min" : "On time"
                let statusColor: NSColor = journey.cancelled
                    ? NSColor(calibratedRed: 0.75, green: 0.12, blue: 0.12, alpha: 1)
                    : journey.delay > 0
                        ? NSColor(calibratedRed: 0.65, green: 0.30, blue: 0, alpha: 1)
                        : NSColor(calibratedRed: 0.08, green: 0.45, blue: 0.20, alpha: 1)
                draw(expected, top: top + 4, height: 30, font: .systemFont(ofSize: 21, weight: .semibold), color: statusColor, x: 180, width: 470)
                draw("Platform \(journey.platform.isEmpty ? "—" : journey.platform)", top: top + 4, height: 30,
                     font: .systemFont(ofSize: 21, weight: .semibold), color: textColor, alignment: .right, x: 650, width: 198)
                draw(journey.destination, top: top + 41, height: 26, font: .systemFont(ofSize: 18), color: secondaryTextColor, x: 180, width: 668)
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        return bitmap.representation(using: .png, properties: [:])
    }
}
