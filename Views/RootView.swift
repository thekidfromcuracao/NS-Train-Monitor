import SwiftUI

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

#Preview {
    NavigationStack {
        RootView(model: MonitorModel())
    }
    .frame(width: 1100, height: 700)
}

