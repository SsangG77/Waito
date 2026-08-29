import SwiftUI

extension Color {
    static let wPixelOrange = Color(red: 0xE8/255, green: 0xA8/255, blue: 0x38/255)
    static let wPixelBorder = Color(red: 0x1E/255, green: 0x48/255, blue: 0x73/255)
    static let wPixelMuted  = Color(red: 0x73/255, green: 0x94/255, blue: 0xB8/255)
    static let wPixelGreen  = Color(red: 0x22/255, green: 0xC5/255, blue: 0x5E/255)
    // 앱 pixelRed(0x7B2433)와 동일 — 잠금화면 BOUNCE 버튼(빨강 ADD 버튼 스타일)용
    static let wPixelRed    = Color(red: 0x7B/255, green: 0x24/255, blue: 0x33/255)
}

// MARK: - 위젯용 픽셀 박스 (앱 PixelTheme 의 NotchedRectangle/PixelBorderShape 복제)
// PixelTheme 는 앱 타깃 전용이라 위젯에서 못 씀 → 동일한 모양을 위젯에 self-contained 로 둔다.

/// 모서리가 90도 안쪽으로 꺾이는 배경 클립용 shape
struct WNotchedRectangle: Shape {
    var notch: CGFloat
    func path(in rect: CGRect) -> Path {
        let n = notch
        var p = Path()
        p.move(to:    CGPoint(x: rect.minX + n, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - n, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - n, y: rect.minY + n))
        p.addLine(to: CGPoint(x: rect.maxX,     y: rect.minY + n))
        p.addLine(to: CGPoint(x: rect.maxX,     y: rect.maxY - n))
        p.addLine(to: CGPoint(x: rect.maxX - n, y: rect.maxY - n))
        p.addLine(to: CGPoint(x: rect.maxX - n, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + n, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + n, y: rect.maxY - n))
        p.addLine(to: CGPoint(x: rect.minX,     y: rect.maxY - n))
        p.addLine(to: CGPoint(x: rect.minX,     y: rect.minY + n))
        p.addLine(to: CGPoint(x: rect.minX + n, y: rect.minY + n))
        p.addLine(to: CGPoint(x: rect.minX + n, y: rect.minY))
        p.closeSubpath()
        return p
    }
}

/// 모서리에서 선이 끊기는 4선 테두리
struct WPixelBorderShape: Shape {
    var cornerGap: CGFloat = 4
    func path(in rect: CGRect) -> Path {
        let g = cornerGap
        var path = Path()
        path.move(to:    CGPoint(x: rect.minX + g, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - g, y: rect.minY))
        path.move(to:    CGPoint(x: rect.maxX,     y: rect.minY + g))
        path.addLine(to: CGPoint(x: rect.maxX,     y: rect.maxY - g))
        path.move(to:    CGPoint(x: rect.maxX - g, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + g, y: rect.maxY))
        path.move(to:    CGPoint(x: rect.minX,     y: rect.maxY - g))
        path.addLine(to: CGPoint(x: rect.minX,     y: rect.minY + g))
        return path
    }
}

extension View {
    /// 앱의 pixelBox 와 동일한 노치 + 끊긴 테두리 박스(위젯용)
    func wPixelBox(border: Color, bg: Color, lineWidth: CGFloat = 2, notch: CGFloat = 4) -> some View {
        self
            .background(bg.clipShape(WNotchedRectangle(notch: notch)))
            .overlay(WPixelBorderShape(cornerGap: notch).stroke(border, lineWidth: lineWidth))
    }
}

func wPixelStatusColor(_ status: DeliveryStatus) -> Color {
    switch status {
    case .delivered:  return .wPixelGreen
    case .registered: return .wPixelMuted
    default:          return .wPixelOrange
    }
}
