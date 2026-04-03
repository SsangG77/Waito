import ActivityKit
import Foundation

// MARK: - 개별 택배 상태 (Live Activity 내부에서 사용)

struct TrackingItemState: Codable, Hashable {
    var trackingNumber: String
    var status: DeliveryStatus
    var carrierName: String
    var itemName: String
    var estimatedDelivery: String?
}

// MARK: - Live Activity Attributes

struct DeliveryAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// 추적 중인 택배 목록 (무료 1개, 유료 2개)
        var items: [TrackingItemState]
        var truckConfig: TruckConfig = .default

        // 편의 접근자 — 첫 번째(주) 택배
        var primary: TrackingItemState? { items.first }
        var secondary: TrackingItemState? { items.count > 1 ? items[1] : nil }
    }

    /// 디바이스 식별용
    var deviceId: String
}
