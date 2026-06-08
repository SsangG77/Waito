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
    /// 운송장 조회 실패(NOT_FOUND)에도 강제로 추가할지 여부
    let force: Bool?
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
    let currentStatus: DeliveryStatus
    let currentTValue: CGFloat
    let carrierName: String
    let estimatedDelivery: String?
    let createdAt: String
    let updatedAt: String?
    let lastEventTime: String?
    let deliveredAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case carrierId = "carrier_id"
        case trackingNumber = "tracking_number"
        case itemName = "item_name"
        case currentStatus = "current_status"
        case currentTValue = "current_t_value"
        case carrierName = "carrier_name"
        case estimatedDelivery = "estimated_delivery"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case lastEventTime = "last_event_time"
        case deliveredAt = "delivered_at"
    }

    /// 한 번이라도 조회에 성공해 이벤트를 받았는지. nil 이면 "아직 데이터 없음"
    var hasTrackingData: Bool { lastEventTime != nil }

    // 더미/프리뷰 생성 코드 호환을 위해 updatedAt / lastEventTime 은 기본값 nil
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
        updatedAt: String? = nil,
        lastEventTime: String? = nil
    ) {
        self.id = id
        self.carrierId = carrierId
        self.trackingNumber = trackingNumber
        self.itemName = itemName
        self.currentStatus = currentStatus
        self.currentTValue = currentTValue
        self.carrierName = carrierName
        self.estimatedDelivery = estimatedDelivery
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastEventTime = lastEventTime
        self.deliveredAt = deliveredAt
    }
}

// MARK: - Tracking Detail

struct TrackingDetail: Decodable, Identifiable {
    let id: Int
    let carrierId: String
    let trackingNumber: String
    let itemName: String
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

// MARK: - API Error

struct APIErrorResponse: Decodable {
    let error: String
    let message: String?
}
