import Foundation
import Combine

/// User preferences, backed by UserDefaults.
final class Preferences: ObservableObject {
    static let shared = Preferences()

    private let defaults = UserDefaults.standard

    enum Keys {
        static let dropZonesEnabled = "dropZonesEnabled"
    }

    @Published var dropZonesEnabled: Bool {
        didSet { defaults.set(dropZonesEnabled, forKey: Keys.dropZonesEnabled) }
    }

    private init() {
        defaults.register(defaults: [
            Keys.dropZonesEnabled: true,
        ])
        self.dropZonesEnabled = defaults.bool(forKey: Keys.dropZonesEnabled)
    }

}
