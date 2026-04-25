import SwiftUI

// MARK: - 트럭 모양 3종

enum TruckShape: String, Codable, CaseIterable {
    case standard    // 기본 배송 트럭
    case minivan     // 미니 밴
    case heavy       // 대형 트럭

    var displayName: String {
        switch self {
        case .standard: return "기본 트럭"
        case .minivan:  return "미니밴"
        case .heavy:    return "대형 트럭"
        }
    }
}

// MARK: - 그림체 3종

enum TruckStyle: String, Codable, CaseIterable {
    case flat        // 깔끔한 단색
    case pixel       // 도트/픽셀
    case threeD      // 그라데이션/그림자

    var displayName: String {
        switch self {
        case .flat:    return "플랫"
        case .pixel:   return "픽셀"
        case .threeD:  return "3D"
        }
    }
}

// MARK: - 프리셋 색상 팔레트

enum TruckColor: String, Codable, CaseIterable, Hashable {
    case white, black, red, blue, green, yellow, orange, purple, pink, gray

    var color: Color {
        switch self {
        case .white:  return .white
        case .black:  return Color(white: 0.15)
        case .red:    return Color(red: 0.9, green: 0.25, blue: 0.2)
        case .blue:   return Color(red: 0.2, green: 0.5, blue: 0.95)
        case .green:  return Color(red: 0.2, green: 0.78, blue: 0.35)
        case .yellow: return Color(red: 1.0, green: 0.84, blue: 0.04)
        case .orange: return Color(red: 1.0, green: 0.58, blue: 0.0)
        case .purple: return Color(red: 0.58, green: 0.25, blue: 0.92)
        case .pink:   return Color(red: 1.0, green: 0.42, blue: 0.58)
        case .gray:   return Color(white: 0.55)
        }
    }

    var displayName: String {
        switch self {
        case .white:  return "화이트"
        case .black:  return "블랙"
        case .red:    return "레드"
        case .blue:   return "블루"
        case .green:  return "그린"
        case .yellow: return "옐로"
        case .orange: return "오렌지"
        case .purple: return "퍼플"
        case .pink:   return "핑크"
        case .gray:   return "그레이"
        }
    }
}

// MARK: - 트럭 전체 설정

// MARK: - 트럭 달리기 모드

enum TruckRunMode: String, Codable, CaseIterable {
    case on   // 트럭이 진행률과 무관하게 계속 달림 (꾸미기 모드)
    case off  // 트럭이 진행률 끝에 멈춤 (상태 표시 모드)

    var displayName: String {
        switch self {
        case .on:  return "달리기"
        case .off: return "상태 표시"
        }
    }
}

// MARK: - 트럭 전체 설정

struct TruckConfig: Codable, Equatable, Hashable {
    var shape: TruckShape = .standard
    var style: TruckStyle = .flat
    var headColor: TruckColor = .blue
    var cargoColor: TruckColor = .white
    var boxColor: TruckColor = .orange
    var runMode: TruckRunMode = .off

    // catalog 조합 필드
    var cab: TruckCab = .blue
    var body: TruckBody = .express
    var wheelType: TruckWheelType = .standard

    static let `default` = TruckConfig()
}
