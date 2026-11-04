import Foundation
import ServiceManagement

/// Wraps macOS 13+ `SMAppService.mainApp` to toggle "launch at login" for the
/// app itself. Only functional when running from a proper .app bundle (the raw
/// SPM binary has no bundle identifier to register).
enum LoginItem {
    /// Whether the app is currently registered to launch at login.
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// True when we're running as a registrable bundle (not the bare binary).
    static var isAvailable: Bool {
        Bundle.main.bundleIdentifier != nil
    }

    /// Register or unregister the login item. Returns true on success.
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        guard isAvailable else { return false }
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
            return true
        } catch {
            NSLog("DropShelf: login item toggle failed: \(error)")
            return false
        }
    }
}
