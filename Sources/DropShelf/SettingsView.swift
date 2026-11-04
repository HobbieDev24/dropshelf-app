import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject var prefs: Preferences
    @EnvironmentObject var store: ShelfStore

    var body: some View {
        GeneralSettingsTab()
        .frame(width: 560, height: 460)
    }
}

// MARK: - General

struct GeneralSettingsTab: View {
    @EnvironmentObject var prefs: Preferences
    @State private var launchAtLogin = LoginItem.isEnabled

    var body: some View {
        Form {
            Section {
                Toggle("Show drop zones when dragging files", isOn: $prefs.dropZonesEnabled)
            } header: {
                Text("Behavior")
            }
            Section {
                Toggle("Launch DropShelf at login", isOn: $launchAtLogin)
                    .disabled(!LoginItem.isAvailable)
                    .onChange(of: launchAtLogin) { newValue in
                        let ok = LoginItem.setEnabled(newValue)
                        // Reflect the true system state (revert if it failed).
                        if !ok || LoginItem.isEnabled != newValue {
                            launchAtLogin = LoginItem.isEnabled
                        }
                    }
                if !LoginItem.isAvailable {
                    Text("Available when running the built app bundle.")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            } header: {
                Text("Startup")
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear { launchAtLogin = LoginItem.isEnabled }
    }
}
