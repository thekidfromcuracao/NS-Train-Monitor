import SwiftUI

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

#Preview {
    ActivityView(model: MonitorModel())
        .frame(width: 800, height: 600)
}

