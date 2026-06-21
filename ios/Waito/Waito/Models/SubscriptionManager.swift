import Foundation
import Observation

@MainActor
@Observable
final class SubscriptionManager {
    /// 구독 상태 저장 키 — TrackingService 등 다른 레이어가 UserDefaults로 방어적 재확인할 때 공유한다.
    static let storageKey = "waito_is_subscribed"

    private(set) var isSubscribed: Bool

    init() {
        self.isSubscribed = UserDefaults.standard.bool(forKey: Self.storageKey)
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

    // MARK: - Live Activity 제한

    var liveActivityLimit: Int {
        isSubscribed ? 2 : 1
    }

    // MARK: - 항상 노출 (배송 없어도 Dynamic Island 트럭 유지) — 구독 전용

    var canUseAlwaysShow: Bool {
        isSubscribed
    }

    // MARK: - 디버그용 토글 (나중에 StoreKit으로 교체)

    func toggleSubscription() {
        isSubscribed.toggle()
        UserDefaults.standard.set(isSubscribed, forKey: Self.storageKey)
    }

    /// 디버그 언락(설정 비밀번호) 등에서 구독 상태를 명시적으로 설정한다.
    func setSubscribed(_ value: Bool) {
        isSubscribed = value
        UserDefaults.standard.set(value, forKey: Self.storageKey)
    }
}
