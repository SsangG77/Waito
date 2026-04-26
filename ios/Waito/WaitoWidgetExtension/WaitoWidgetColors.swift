import SwiftUI

extension Color {
    static let wPixelOrange = Color(red: 0xE8/255, green: 0xA8/255, blue: 0x38/255)
    static let wPixelBorder = Color(red: 0x1E/255, green: 0x48/255, blue: 0x73/255)
    static let wPixelMuted  = Color(red: 0x73/255, green: 0x94/255, blue: 0xB8/255)
    static let wPixelGreen  = Color(red: 0x22/255, green: 0xC5/255, blue: 0x5E/255)
}

func wPixelStatusColor(_ status: DeliveryStatus) -> Color {
    switch status {
    case .delivered:  return .wPixelGreen
    case .registered: return .wPixelMuted
    default:          return .wPixelOrange
    }
}
