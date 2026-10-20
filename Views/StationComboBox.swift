import SwiftUI
import AppKit

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

#Preview {
    @Previewable @State var selection = MonitorPlan().departureCode

    StationComboBox(stations: MonitorModel.fallbackStations, selection: $selection)
        .frame(width: 300, height: 26)
        .padding()
}

