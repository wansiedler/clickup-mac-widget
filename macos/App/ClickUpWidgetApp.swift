import SwiftUI
import WidgetKit

/// Host app: only exists to hold the token and ship the widget extension.
@main
struct ClickUpWidgetApp: App {
    var body: some Scene {
        WindowGroup("ClickUp Widget") {
            SettingsView().frame(minWidth: 440, minHeight: 280)
        }
        .windowResizability(.contentSize)
    }
}

struct SettingsView: View {
    @State private var token = TokenStore.read(.token) ?? ""
    @State private var teamId = TokenStore.read(.teamId) ?? ""
    @State private var workspaces: [Workspace] = []
    @State private var status = ""
    @State private var busy = false

    var body: some View {
        Form {
            Section("API token") {
                SecureField("pk_…", text: $token)
                Text("ClickUp → avatar → Settings → Apps → API Token")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Workspace") {
                Picker("Workspace", selection: $teamId) {
                    Text("First available").tag("")
                    ForEach(workspaces) { Text($0.name).tag($0.id) }
                }
            }
            HStack {
                Button("Save & test") { Task { await save() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(busy || token.isEmpty)
                if busy { ProgressView().controlSize(.small) }
                Text(status).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .formStyle(.grouped)
        .padding()
        .task { if !token.isEmpty { await test() } }
    }

    private func save() async {
        let a = TokenStore.write(.token, token)
        let b = TokenStore.write(.teamId, teamId)
        guard a == errSecSuccess, b == errSecSuccess else {
            status = "Keychain write failed (\(a), \(b)). Check signing / keychain group."
            return
        }
        await test()
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func test() async {
        busy = true
        defer { busy = false }
        do {
            let api = ClickUpAPI(token: token)
            workspaces = try await api.workspaces()
            let s = try await api.snapshot(teamOverride: teamId)
            status = "OK: \(s.overdue.count) overdue, \(s.today.count) today, \(s.upcoming.count) upcoming"
                + (s.timer == nil ? "" : ", timer running")
        } catch {
            status = error.localizedDescription
        }
    }
}
