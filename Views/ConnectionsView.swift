import SwiftUI

struct ConnectionsView: View {
    @ObservedObject var model: MonitorModel
    @State private var topic: String; @State private var key: String; @State private var liveNDOV: Bool
    init(model: MonitorModel) {
        self.model = model
        _topic = State(initialValue: model.settings.ntfyTopic)
        _key = State(initialValue: model.apiKey)
        _liveNDOV = State(initialValue: model.settings.usesLiveNDOV)
    }
    var body: some View { VStack(spacing: 0) {
        HStack { VStack(alignment: .leading) { Text("Connections").font(.largeTitle.bold()); Text("NS journey data, live updates and phone notifications").foregroundStyle(.secondary) }; Spacer(); Button("Save") { model.saveConnection(AppSettings(ntfyTopic: topic, liveNDOVEnabled: liveNDOV), key) }.buttonStyle(.borderedProminent).disabled(topic == model.settings.ntfyTopic && key == model.apiKey && liveNDOV == model.settings.usesLiveNDOV) }.padding(28)
        Form {
            Section("NS API") { SecureField("Subscription key", text: $key); Text("Stored securely in macOS Keychain.").font(.caption).foregroundStyle(.secondary) }
            Section("Live departure updates") {
                Toggle("Use NDOV live updates (experimental)", isOn: $liveNDOV)
                HStack(spacing: 8) {
                    Circle().fill(model.ndovState.color).frame(width: 8, height: 8)
                    Text(liveNDOV ? model.ndovState.title : "Off")
                }
                .font(.caption)
                Text("When enabled, live station events trigger a fresh NS journey check. Your check interval is kept as an automatic fallback if the live feed disconnects.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Notifications") {
                TextField("ntfy topic", text: $topic)
                HStack {
                    Button("Send test notification + card") { model.testNotification(topic: topic) }.disabled(topic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.testingNotification)
                    if model.testingNotification { ProgressView().controlSize(.small) }
                }
                if let result = model.connectionTestMessage {
                    Text(result).font(.caption).foregroundStyle(result.hasPrefix("Test failed") ? .red : .green)
                }
                Text("Test always sends. Daily summaries are sent once per monitor; later checks notify only when a journey changes.").font(.caption).foregroundStyle(.secondary)
            }
            Section { Button("Refresh station list") { model.saveConnection(AppSettings(ntfyTopic: topic, liveNDOVEnabled: liveNDOV), key) }.disabled(key.isEmpty) }
        }.formStyle(.grouped).padding().frame(maxWidth: 650)
        Spacer()
    }.onAppear { topic = model.settings.ntfyTopic; key = model.apiKey; liveNDOV = model.settings.usesLiveNDOV } }
}

#Preview {
    ConnectionsView(model: MonitorModel())
        .frame(width: 800, height: 700)
}

