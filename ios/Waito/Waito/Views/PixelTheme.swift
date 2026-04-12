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

// MARK: - PixelAlert

struct PixelAlert: View {
    let title: String
    let message: String
    let buttonTitle: String
    let onConfirm: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                // 타이틀
                Text(title.uppercased())
                    .font(pixelFont(11))
                    .foregroundStyle(Color.pixelOrange)
                    .padding(.horizontal, 18)
                    .padding(.top, 18)
                    .padding(.bottom, 12)

                Rectangle()
                    .fill(Color.pixelBorder)
                    .frame(height: 1)
                    .padding(.horizontal, 18)

                // 메시지
                Text(message)
                    .font(pixelFont(8))
                    .foregroundStyle(Color.pixelText)
                    .lineSpacing(5)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)

                Rectangle()
                    .fill(Color.pixelBorder)
                    .frame(height: 1)
                    .padding(.horizontal, 18)

                // 확인 버튼
                Button {
                    onConfirm()
                } label: {
                    Text("> \(buttonTitle.uppercased())_")
                        .font(pixelFont(9))
                        .foregroundStyle(Color.pixelOrange)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.plain)
            }
            .pixelBox(border: Color.pixelBorder, bg: Color.pixelSurface, lineWidth: 1.5, notch: 8)
            .padding(.horizontal, 40)
        }
    }
}

extension View {
    func pixelAlert(
        title: String,
        message: String,
        buttonTitle: String = "확인",
        isPresented: Binding<Bool>,
        onConfirm: @escaping () -> Void = {}
    ) -> some View {
        ZStack {
            self
            if isPresented.wrappedValue {
                PixelAlert(title: title, message: message, buttonTitle: buttonTitle) {
                    onConfirm()
                    isPresented.wrappedValue = false
                }
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isPresented.wrappedValue)
                .zIndex(999)
            }
        }
    }
}

// MARK: - Previews

//#Preview("PixelBox") {
//    VStack(spacing: 20) {
//        Text("ITEM NAME")
//            .font(pixelFont(12))
//            .foregroundStyle(Color.pixelText)
//            .padding(16)
//            .pixelBox()
//
//        Text("ACTIVE")
//            .font(pixelFont(10))
//            .foregroundStyle(Color.pixelOrange)
//            .padding(12)
//            .pixelBox(border: Color.pixelOrange, bg: Color.pixelSurface)
//
//        Text("COMPLETED")
//            .font(pixelFont(10))
//            .foregroundStyle(Color(hex: "#22C55E"))
//            .padding(12)
//            .pixelBox(border: Color(hex: "#22C55E"), bg: Color.pixelSurface)
//    }
//    .padding(24)
//    .background(Color.bg)
//}
//
//#Preview("PixelTextField & PixelButton") {
//    VStack(spacing: 20) {
//        PixelTextField(label: "TRACKING NO.", text: .constant("123456789"))
//        PixelTextField(label: "ITEM NAME", text: .constant(""))
//        PixelButton(title: "ADD") {}
//    }
//    .padding(24)
//    .background(Color.bg)
//}

#Preview("PixelAlert") {
    Color.bg
        .ignoresSafeArea()
        .pixelAlert(
            title: "오류",
            message: "서버에 연결할 수 없어요.\n잠시 후 다시 시도해주세요.",
            isPresented: .constant(true)
        )
}

