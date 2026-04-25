import Foundation

// MARK: - TruckCab

enum TruckCab: String, CaseIterable, Codable, Hashable {
    case black
    case blue
    case brown
    case cream
    case green
    case mint
    case navy
    case orangeBar
    case pink
    case purple
    case redStack
    case yellowBeacon

    var imageName: String {
        switch self {
        case .orangeBar:     return "cab_orange_bar"
        case .redStack:      return "cab_red_stack"
        case .yellowBeacon:  return "cab_yellow_beacon"
        default:             return "cab_\(rawValue)"
        }
    }

    var displayName: String {
        switch self {
        case .black:         return "블랙"
        case .blue:          return "블루"
        case .brown:         return "브라운"
        case .cream:         return "크림"
        case .green:         return "그린"
        case .mint:          return "민트"
        case .navy:          return "네이비"
        case .orangeBar:     return "오렌지바"
        case .pink:          return "핑크"
        case .purple:        return "퍼플"
        case .redStack:      return "레드스택"
        case .yellowBeacon:  return "옐로비콘"
        }
    }

    var requiresPlus: Bool { self != .blue }
}

// MARK: - TruckBody

enum TruckBody: String, CaseIterable, Codable, Hashable {
    case boxes
    case container
    case dump
    case express
    case flatbed
    case food
    case garbage
    case moving
    case orange
    case reefer
    case semi
    case tanker

    var imageName: String { "body_\(rawValue)" }

    var displayName: String {
        switch self {
        case .boxes:     return "박스"
        case .container: return "컨테이너"
        case .dump:      return "덤프"
        case .express:   return "택배"
        case .flatbed:   return "플랫베드"
        case .food:      return "푸드"
        case .garbage:   return "환경"
        case .moving:    return "이사"
        case .orange:    return "오렌지"
        case .reefer:    return "냉동"
        case .semi:      return "세미"
        case .tanker:    return "탱커"
        }
    }

    var requiresPlus: Bool { self != .express }
}

// MARK: - TruckWheelType

enum TruckWheelType: String, CaseIterable, Codable, Hashable {
    case standard
    case chrome
    case flame
    case gold
    case heavy
    case mud
    case neon
    case offroad
    case red
    case small
    case spokes
    case whitewall

    var imageName: String { "wheels_\(rawValue)" }

    var displayName: String {
        switch self {
        case .standard:  return "기본"
        case .chrome:    return "크롬"
        case .flame:     return "불꽃"
        case .gold:      return "골드"
        case .heavy:     return "헤비"
        case .mud:       return "머드"
        case .neon:      return "네온"
        case .offroad:   return "오프로드"
        case .red:       return "레드"
        case .small:     return "스몰"
        case .spokes:    return "스포크"
        case .whitewall: return "화이트월"
        }
    }

    var requiresPlus: Bool { self != .standard }
}
