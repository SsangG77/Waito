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

    // catalog 조합 필드 (무료 기본 트럭: 소프트블루 헤드 + 택배 바디 + 기본 바퀴)
    var cab: TruckCab = .truckSoftBlue
    var body: TruckBody = .truckExpressBlack
    var wheelType: TruckWheelType = .standard

    static let `default` = TruckConfig()
}

// MARK: - 견고한 디코딩
// 서버 push(content-state.truckConfig)나 구버전/스키마 진화로 일부 키가 빠지거나
// 잘못된 enum raw 값이 와도, 해당 필드만 기본값으로 폴백한다.
// (합성 Decodable 은 키 누락/잘못된 값에서 throw → ContentState 전체 디코딩 실패를 유발하므로 커스텀)
// extension 에 두어 본체의 memberwise init(= .default) 은 그대로 유지.
extension TruckConfig {
    private enum CodingKeys: String, CodingKey {
        case shape, style, headColor, cargoColor, boxColor, runMode, cab, body, wheelType
    }

    init(from decoder: Decoder) throws {
        self.init()
        guard let c = try? decoder.container(keyedBy: CodingKeys.self) else { return }
        shape      = (try? c.decode(TruckShape.self,     forKey: .shape))      ?? shape
        style      = (try? c.decode(TruckStyle.self,     forKey: .style))      ?? style
        headColor  = (try? c.decode(TruckColor.self,     forKey: .headColor))  ?? headColor
        cargoColor = (try? c.decode(TruckColor.self,     forKey: .cargoColor)) ?? cargoColor
        boxColor   = (try? c.decode(TruckColor.self,     forKey: .boxColor))   ?? boxColor
        runMode    = (try? c.decode(TruckRunMode.self,   forKey: .runMode))    ?? runMode
        cab        = (try? c.decode(TruckCab.self,       forKey: .cab))        ?? cab
        body       = (try? c.decode(TruckBody.self,      forKey: .body))       ?? body
        wheelType  = (try? c.decode(TruckWheelType.self, forKey: .wheelType))  ?? wheelType
    }
}
