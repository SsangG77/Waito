import ActivityKit
import Foundation

// MARK: - 개별 택배 상태 (Live Activity 내부에서 사용)

struct TrackingItemState: Codable, Hashable {
    var trackingNumber: String
    var status: DeliveryStatus
    var carrierName: String
    var itemName: String
    var estimatedDelivery: String?

    // 가변 이벤트 타임라인용 compact 필드 (위젯 타깃은 TrackingEvent 전체를 못 보므로
    // 개수 + 최신 라벨만 전달). ⚠️ 반드시 Optional — 기본값을 주면 합성 Codable 이 키를
    // 필수로 간주해, 구버전 push/persisted Activity 디코딩이 실패하며 Activity 가 사라진다.
    var eventCount: Int?
    /// 마지막(현재) 이벤트의 원본 택배사 설명. nil 이면 status.displayName 으로 폴백.
    var statusLabel: String?
    /// 출발(등록) 날짜 — 목록의 createdAt 원본 문자열. 위젯에서 짧게 포맷해 표시.
    var departureDate: String?
}

// MARK: - Live Activity Attributes

struct DeliveryAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// 추적 중인 택배 목록 (무료 1개, 유료 2개)
        var items: [TrackingItemState]
        var truckConfig: TruckConfig = .default

        /// idle(항상 노출) 트럭의 세로 오프셋(pt). 앱이 활동 시작 시 이 값을 위/아래로
        /// 몇 번 갱신하면 시스템이 전환을 애니메이션해 "바운스"처럼 보인다.
        /// ⚠️ Optional 필수(기본값 주면 구 payload 디코딩 실패). nil = 오프셋 0.
        var truckBounce: Double?

        // 편의 접근자 — 첫 번째(주) 택배
        var primary: TrackingItemState? { items.first }
        var secondary: TrackingItemState? { items.count > 1 ? items[1] : nil }
    }

    /// 디바이스 식별용
    var deviceId: String
}
