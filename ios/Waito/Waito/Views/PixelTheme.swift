import SwiftUI

// MARK: - Color Extensions

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8)  & 0xFF) / 255
        let b = Double( int        & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }

}

// MARK: - Pixel Font

func pixelFont(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
    .system(size: size, design: .monospaced).weight(weight)
}

// MARK: - NotchedRectangle
// 모서리가 90도 안쪽으로 꺾이는 배경 클립용 shape

struct NotchedRectangle: Shape {
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

// MARK: - PixelBorderShape
// 모서리에서 선이 끊기는 4선 테두리

struct PixelBorderShape: Shape {
    var cornerGap: CGFloat = 10

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

// MARK: - PixelBox Modifier

struct PixelBox: ViewModifier {
    var borderColor: Color = .pixelBorder
    var bgColor: Color = .pixelSurface
    var lineWidth: CGFloat
    var notch: CGFloat

    func body(content: Content) -> some View {
        content
            .background(bgColor.clipShape(NotchedRectangle(notch: notch)))
            .overlay(
                PixelBorderShape(cornerGap: notch)
                    .stroke(borderColor, lineWidth: lineWidth)
            )
    }
}

extension View {
    func pixelBox(
        border: Color = .pixelBorder,
        bg: Color = .pixelSurface,
        lineWidth: CGFloat = 2,
        notch: CGFloat = 4
    ) -> some View {
        modifier(PixelBox(borderColor: border, bgColor: bg, lineWidth: lineWidth, notch: notch))
    }
}

// MARK: - PixelTextField

struct PixelTextField: View {
    let label: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(pixelFont(9))
                .foregroundStyle(Color.pixelOrange)

            TextField("", text: $text)
                .font(pixelFont(10))
                .foregroundStyle(Color.pixelText)
                .tint(Color.pixelOrange)
                .padding(.horizontal, 12)
                .padding(.vertical, 14)
                .pixelBox()
        }
    }
}

// MARK: - PixelButton

struct PixelButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(">")
                Text("\(title)_")
            }
            .font(pixelFont(11))
            .foregroundStyle(Color.pixelText)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .pixelBox(border: Color.pixelRed.opacity(0.7), bg: Color.pixelRed)
        }
        .buttonStyle(.plain)
    }
}
