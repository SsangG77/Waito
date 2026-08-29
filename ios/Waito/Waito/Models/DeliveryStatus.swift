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

    // 표시 전용 진행도(게이지·트럭 위치). 5단계(택배사 코드) 균등 배분.
    // deprecated 인 inTransitOut/delivering 은 각각 병합 대상(간선/배송출발)과 같은 값.
    var progress: CGFloat {
        switch self {
        case .registered:                  return 0.1
        case .pickedUp:                    return 0.3
        case .inTransitIn, .inTransitOut:  return 0.5   // 간선
        case .outForDelivery, .delivering: return 0.7   // 배송출발
        case .delivered:                   return 0.9
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

    // MARK: - 표시 단계 = 택배사 코드 5단계

    /// 화면 표시 단계 = tracker.delivery 코드 5개(접수·집화완료·간선·배송출발·배송완료).
    /// 간선상차/하차·배송중 세분화는 폐기 → 각각 간선(inTransitIn)/배송출발(outForDelivery)로 병합 표시.
    static let collapsedStages: [DeliveryStatus] = [.registered, .pickedUp, .inTransitIn, .outForDelivery, .delivered]

    /// 현재 상태가 위 5단계 중 몇 번째인지(채움 기준). 간선하차→간선(2), 배송중→배송출발(3).
    var collapsedStepIndex: Int {
        switch self {
        case .registered:                  return 0
        case .pickedUp:                    return 1
        case .inTransitIn, .inTransitOut:  return 2
        case .outForDelivery, .delivering: return 3
        case .delivered:                   return 4
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

// MARK: - 타임라인 표시 단계 (국내 5단계 / 해외 6단계)

/// 타임라인·진행 게이지가 쓰는 "표시 단계"를 한 곳에서 계산한다.
/// 국내 = 기존 5단계(collapsedStages). 해외 = 통관을 포함한 6단계.
///
/// 해외는 status enum 을 늘리지 않고(구버전 payload 디코딩 깨짐) 옵셔널 subStage('customs')로
/// 통관 여부를 받는다 — 통관 이력이 생기면 서버가 유지하므로 트럭이 뒤로 가지 않는다.
struct DeliveryStageInfo {
    /// 단계 라벨 (등장 순서대로)
    let names: [String]
    /// 현재 단계 인덱스 (채움 기준)
    let currentIndex: Int

    var count: Int { names.count }
    /// 현재 단계 라벨 — 해외 통관 구간이면 "통관"이 나온다.
    var currentName: String { names[currentIndex] }
    /// 진행 게이지(원형 링·가로 바) — 단계 수 기준 균등 배분.
    /// 국내 5단계일 때 기존 progress(0.1/0.3/…)와 동일한 값이 나온다.
    var progress: CGFloat { CGFloat(currentIndex * 2 + 1) / CGFloat(count * 2) }

    init(status: DeliveryStatus, isInternational: Bool, subStage: String?) {
        if isInternational {
            names = ["접수", "발송", "국제운송", "통관", "배송출발", "배송완료"]
            let inCustoms = subStage == "customs"
            switch status {
            case .registered:                  currentIndex = 0
            case .pickedUp:                    currentIndex = 1
            case .inTransitIn, .inTransitOut:  currentIndex = inCustoms ? 3 : 2
            case .outForDelivery, .delivering: currentIndex = 4
            case .delivered:                   currentIndex = 5
            }
        } else {
            names = DeliveryStatus.collapsedStages.map(\.displayName)
            currentIndex = status.collapsedStepIndex
        }
    }
}
