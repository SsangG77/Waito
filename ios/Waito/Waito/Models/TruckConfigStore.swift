import Foundation
import Observation

@Observable
final class TruckConfigStore {
    static let shared = TruckConfigStore()

    var config: TruckConfig {
        didSet { save() }
    }

    private let key = "waito_truck_config"

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode(TruckConfig.self, from: data) {
            self.config = saved
        } else {
            self.config = .default
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
