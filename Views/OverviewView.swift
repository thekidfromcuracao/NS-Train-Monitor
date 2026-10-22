import SwiftUI

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
                Button { model.toggle(p) } label: {
                    Text(model.running.contains(p.id) ? "Stop" : "Start")
                        .frame(minWidth: 32)
                }.buttonStyle(MonitorSecondaryButtonStyle(isProminent: true))
                Button("Check now") { model.checkNow(p) }.buttonStyle(MonitorSecondaryButtonStyle()).disabled(model.working.contains(p.id))
                Button("Edit") { edit(p) }.buttonStyle(MonitorSecondaryButtonStyle())
                Spacer(); if model.working.contains(p.id) { ProgressView().controlSize(.small) }
            }
            if let rows = model.journeys[p.id], !rows.isEmpty { Divider(); ForEach(rows) { j in HStack { Text(j.planned).font(.headline.monospacedDigit()).frame(width: 55, alignment: .leading); VStack(alignment: .leading) { Text(j.destination); Text(j.status).font(.caption).foregroundStyle(j.cancelled ? .red : j.delay > 0 ? .orange : .secondary) }; Spacer(); Text(j.platform.isEmpty ? "—" : j.platform).bold() } } }
        }.padding(20).background(.background, in: RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(.quaternary)) }
        if model.plans.isEmpty { ContentUnavailableView("No monitors", systemImage: "tram", description: Text("Use + to add a route.")) }
    }.padding(28) }.background(Color(nsColor: .windowBackgroundColor)) }
}

#Preview {
    OverviewView(model: MonitorModel(), edit: { _ in }, add: {})
        .frame(width: 1000, height: 600)
}

