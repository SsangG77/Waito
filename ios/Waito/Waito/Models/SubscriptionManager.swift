import Foundation
import Observation

@Observable
final class SubscriptionManager {
    private(set) var isSubscribed: Bool

    private let key = "waito_is_subscribed"

    init() {
        self.isSubscribed = UserDefaults.standard.bool(forKey: key)
    }

    // MARK: - Premium 판별

    func isPremium(shape: TruckShape) -> Bool {
        shape != .standard
    }

    func isPremium(style: TruckStyle) -> Bool {
        style != .flat
    }

    func isPremium(color: TruckColor) -> Bool {
        ![TruckColor.white, .blue, .orange].contains(color)
    }

    func canUse(shape: TruckShape) -> Bool {
        isSubscribed || !isPremium(shape: shape)
    }

    func canUse(style: TruckStyle) -> Bool {
        isSubscribed || !isPremium(style: style)
    }

    func canUse(color: TruckColor) -> Bool {
        isSubscribed || !isPremium(color: color)
    }

    // MARK: - 디버그용 토글 (나중에 StoreKit으로 교체)

    func toggleSubscription() {
        isSubscribed.toggle()
        UserDefaults.standard.set(isSubscribed, forKey: key)
    }
}
