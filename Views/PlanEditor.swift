import SwiftUI

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
                        ForEach(MonitorPlan.orderedWeekdays, id: \.0) { day, label in
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

struct TimePicker: View {
    let title: String; @Binding var value: String
    var date: Binding<Date> { Binding(get: { Self.parser.date(from: value) ?? Date() }, set: { value = Self.parser.string(from: $0) }) }
    var body: some View { DatePicker(title, selection: date, displayedComponents: .hourAndMinute).datePickerStyle(.field) }
    static let parser: DateFormatter = { let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "HH:mm"; return f }()
}

#Preview {
    PlanEditor(model: MonitorModel(), original: nil, draft: MonitorPlan())
}

#Preview {
    @Previewable @State var selected = true

    DayToggle(label: MonitorPlan.orderedWeekdays[0].1, selected: selected) {
        selected.toggle()
    }
    .frame(width: 70)
    .padding()
}

#Preview {
    @Previewable @State var time = MonitorPlan().departureFrom

    TimePicker(title: "From", value: $time)
        .padding()
        .frame(width: 250)
}

