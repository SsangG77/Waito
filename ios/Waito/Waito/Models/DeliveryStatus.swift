import Foundation
import CoreGraphics

enum DeliveryStatus: String, Codable, CaseIterable, Hashable {
    case registered      // 접수
    case pickedUp        // 집화완료
    case inTransitIn     // 간선상차
    case inTransitOut    // 간선하차
    case outForDelivery  // 배송출발
    case delivering      // 배송중
    case delivered       // 배송완료

    // MARK: - t값 (0.0 ~ 1.0) — 트럭의 경로 위 정규화 위치

    var progress: CGFloat {
        switch self {
        case .registered:     return 0.05
        case .pickedUp:       return 0.2
        case .inTransitIn:    return 0.35
        case .inTransitOut:   return 0.5
        case .outForDelivery: return 0.65
        case .delivering:     return 0.8
        case .delivered:      return 0.95
        }
    }

    // MARK: - 한국어 표시명

    var displayName: String {
        switch self {
        case .registered:     return "접수"
        case .pickedUp:       return "집화완료"
        case .inTransitIn:    return "간선상차"
        case .inTransitOut:   return "간선하차"
        case .outForDelivery: return "배송출발"
        case .delivering:     return "배송중"
        case .delivered:      return "배송완료"
        }
    }

    // MARK: - 접힘(간략) 진행바 고정 6단계

    /// 접힘 진행바는 어느 택배든 이 6단계로 과정을 고정 표시(간선하차는 간선상차에 병합).
    static let collapsedStages: [DeliveryStatus] = [.registered, .pickedUp, .inTransitIn, .outForDelivery, .delivering, .delivered]

    /// 현재 상태가 위 6단계 중 몇 번째인지(채움 기준). 간선하차 → 간선상차(2).
    var collapsedStepIndex: Int {
        switch self {
        case .registered:     return 0
        case .pickedUp:       return 1
        case .inTransitIn, .inTransitOut: return 2
        case .outForDelivery: return 3
        case .delivering:     return 4
        case .delivered:      return 5
        }
    }

    // MARK: - 단계 순서 (forward-only 비교용)

    var order: Int {
        switch self {
        case .registered:     return 0
        case .pickedUp:       return 1
        case .inTransitIn:    return 2
        case .inTransitOut:   return 3
        case .outForDelivery: return 4
        case .delivering:     return 5
        case .delivered:      return 6
        }
    }

    var isCompleted: Bool { self == .delivered }
    var isActive: Bool { self == .outForDelivery || self == .delivering }
}
