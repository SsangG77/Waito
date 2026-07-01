import Foundation

// MARK: - Carrier

struct Carrier: Codable, Identifiable, Hashable {
    let id: String
    let name: String
}

// MARK: - Device Registration

struct DeviceRegisterRequest: Encodable {
    let deviceToken: String
}

struct DeviceRegisterResponse: Decodable {
    let deviceId: Int
}

// MARK: - Tracking Create

struct TrackingCreateRequest: Encodable {
    let deviceToken: String
    let carrierId: String
    let trackingNumber: String
    let itemName: String?
    let memo: String?
    /// 운송장 조회 실패(NOT_FOUND)에도 강제로 추가할지 여부
    let force: Bool?
}

// MARK: - Tracking Update (품명/메모 수정)

struct TrackingUpdateRequest: Encodable {
    let itemName: String?
    let memo: String?
}

// MARK: - Device Progress (배송완료 포인트 + 해제 부품)

/// GET /api/devices/me, POST /api/devices/unlock-part 공통 응답
struct DeviceProgress: Decodable {
    let deliveredCount: Int     // 배송완료 누적 = 획득 포인트
    let unlockedParts: [String] // 포인트로 해제한 부품 rawValue 목록
}

struct UnlockPartRequest: Encodable {
    let deviceToken: String
    let part: String            // 부품 enum rawValue (= 에셋명)
}

// MARK: - APNs 일반 알림 토큰 등록

struct APNsTokenRegisterRequest: Encodable {
    let deviceToken: String     // 앱 식별 UUID
    let apnsToken: String       // 표준 원격알림 device token (hex)
}

/// POST /api/trackings 응답 (camelCase)
struct TrackingCreateResponse: Decodable {
    let id: Int
    let carrierId: String
    let trackingNumber: String
    let itemName: String
    let status: DeliveryStatus
    let tValue: CGFloat
    let carrierName: String
}

// MARK: - Tracking List Item

/// GET /api/trackings 응답 (snake_case — DB 직접 반환)
struct TrackingListItem: Decodable, Identifiable {
    let id: Int
    let carrierId: String
    let trackingNumber: String
    let itemName: String
    let memo: String?
    let currentStatus: DeliveryStatus
    let currentTValue: CGFloat
    let carrierName: String
    let estimatedDelivery: String?
    let createdAt: String
    let updatedAt: String?
    let lastEventTime: String?
    let deliveredAt: String?
    /// 원본 택배사 이벤트 전체(가변 타임라인용). 서버 목록 API 가 포함해 내려줌.
    /// 배포 순서/구버전 안전을 위해 Optional — 누락 시 nil, 사용처에서 `?? []`.
    let events: [TrackingEvent]?

    enum CodingKeys: String, CodingKey {
        case id
        case carrierId = "carrier_id"
        case trackingNumber = "tracking_number"
        case itemName = "item_name"
        case memo
        case currentStatus = "current_status"
        case currentTValue = "current_t_value"
        case carrierName = "carrier_name"
        case estimatedDelivery = "estimated_delivery"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case lastEventTime = "last_event_time"
        case deliveredAt = "delivered_at"
        case events
    }

    /// 한 번이라도 조회에 성공해 이벤트를 받았는지. nil 이면 "아직 데이터 없음"
    var hasTrackingData: Bool { lastEventTime != nil }

    // 더미/프리뷰 생성 코드 호환을 위해 updatedAt / lastEventTime / events 은 기본값 nil
    init(
        id: Int,
        carrierId: String,
        trackingNumber: String,
        itemName: String,
        currentStatus: DeliveryStatus,
        currentTValue: CGFloat,
        carrierName: String,
        estimatedDelivery: String?,
        createdAt: String,
        deliveredAt: String?,
        memo: String? = nil,
        updatedAt: String? = nil,
        lastEventTime: String? = nil,
        events: [TrackingEvent]? = nil
    ) {
        self.id = id
        self.carrierId = carrierId
        self.trackingNumber = trackingNumber
        self.itemName = itemName
        self.memo = memo
        self.currentStatus = currentStatus
        self.currentTValue = currentTValue
        self.carrierName = carrierName
        self.estimatedDelivery = estimatedDelivery
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastEventTime = lastEventTime
        self.deliveredAt = deliveredAt
        self.events = events
    }
}

// MARK: - Tracking Detail

struct TrackingDetail: Decodable, Identifiable {
    let id: Int
    let carrierId: String
    let trackingNumber: String
    let itemName: String
    let memo: String?
    let currentStatus: DeliveryStatus
    let currentTValue: CGFloat
    let carrierName: String
    let estimatedDelivery: String?
    let liveActivityPushToken: String?
    let lastPolledAt: String?
    let lastEventTime: String?
    let createdAt: String
    let updatedAt: String
    let deliveredAt: String?
    let events: [TrackingEvent]

    enum CodingKeys: String, CodingKey {
        case id
        case carrierId = "carrier_id"
        case trackingNumber = "tracking_number"
        case itemName = "item_name"
        case memo
        case currentStatus = "current_status"
        case currentTValue = "current_t_value"
        case carrierName = "carrier_name"
        case estimatedDelivery = "estimated_delivery"
        case liveActivityPushToken = "live_activity_push_token"
        case lastPolledAt = "last_polled_at"
        case lastEventTime = "last_event_time"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deliveredAt = "delivered_at"
        case events
    }
}

// MARK: - Tracking Event

struct TrackingEvent: Decodable, Identifiable {
    let id: Int
    let trackerStatus: String
    let mappedStatus: String
    let description: String
    let eventTime: String
    let location: String?

    enum CodingKeys: String, CodingKey {
        case id
        case trackerStatus = "tracker_status"
        case mappedStatus = "mapped_status"
        case description
        case eventTime = "event_time"
        case location
    }
}

// MARK: - Push Token Update

struct PushTokenUpdateRequest: Encodable {
    let pushToken: String
}

// MARK: - Push-to-Start Token

/// 디바이스/앱당 1개. 8시간 한도로 종료된 Live Activity 를 서버가 재시작할 때 사용.
/// truckConfig 를 함께 보내 서버가 start 페이로드의 content-state 에 그대로 실어준다.
struct PushToStartTokenRequest: Encodable {
    let deviceToken: String
    let pushToStartToken: String
    let truckConfig: TruckConfig?
}

/// 단일 Live Activity 의 갱신 토큰 + 담긴 택배 id 목록을 디바이스 단위로 서버에 동기화.
/// (nil 필드는 인코딩에서 생략 → 서버가 기존 값 유지. 목록만/토큰만 각각 갱신 가능)
struct LiveActivitySyncRequest: Encodable {
    let deviceToken: String
    let trackingIds: [Int]?
    let pushToken: String?
    let truckConfig: TruckConfig?
}

// MARK: - API Error

struct APIErrorResponse: Decodable {
    let error: String
    let message: String?
}
