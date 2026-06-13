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

// MARK: - PixelDropdown
// 시스템 기본 Menu 대신, 펼치면 픽셀 스타일로 목록이 나타나는 드롭다운

struct PixelDropdownOption: Identifiable, Equatable {
    let id: String
    let name: String
}

struct PixelDropdown: View {
    let label: String
    let options: [PixelDropdownOption]
    @Binding var selectedId: String
    var placeholder: String = "선택해주세요"
    var emptyText: String = "로딩 중..."

    @State private var isOpen = false

    private var selectedName: String {
        options.first(where: { $0.id == selectedId })?.name ?? placeholder
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(pixelFont(9))
                .foregroundStyle(Color.pixelOrange)

            VStack(spacing: 0) {
                // 헤더 — 탭하면 펼침/접힘
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                        isOpen.toggle()
                    }
                } label: {
                    HStack {
                        Text(selectedName)
                            .font(pixelFont(10))
                            .foregroundStyle(selectedId.isEmpty ? Color.pixelMuted : Color.pixelText)
                        Spacer()
                        Text(isOpen ? "▲" : "▼")
                            .font(pixelFont(8))
                            .foregroundStyle(Color.pixelOrange)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                // 펼침 목록
                if isOpen {
                    Rectangle()
                        .fill(Color.pixelBorder)
                        .frame(height: 1)

                    if options.isEmpty {
                        Text(emptyText)
                            .font(pixelFont(10))
                            .foregroundStyle(Color.pixelMuted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 12)
                    } else {
                        ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                            if index > 0 {
                                Rectangle()
                                    .fill(Color.pixelBorder.opacity(0.4))
                                    .frame(height: 1)
                            }
                            optionRow(option)
                        }
                    }
                }
            }
            .pixelBox(
                border: isOpen ? Color.pixelOrange.opacity(0.6) : Color.pixelBorder,
                bg: Color.pixelSurface,
                lineWidth: 1.5,
                notch: 4
            )
        }
    }

    private func optionRow(_ option: PixelDropdownOption) -> some View {
        let isSelected = option.id == selectedId
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                selectedId = option.id
                isOpen = false
            }
        } label: {
            HStack(spacing: 8) {
                Text(isSelected ? ">" : " ")
                    .font(pixelFont(10))
                    .foregroundStyle(Color.pixelOrange)
                Text(option.name)
                    .font(pixelFont(10))
                    .foregroundStyle(isSelected ? Color.pixelOrange : Color.pixelText)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(isSelected ? Color.pixelOrange.opacity(0.08) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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

// MARK: - PixelToggle

struct PixelToggle: View {
    let isOn: Bool
    /// false면 비활성(회색 + 탭 불가). 탭 제스처는 상위 뷰로 전달돼 잠금 안내(Paywall 등)에 쓸 수 있다.
    var isEnabled: Bool = true
    let onToggle: () -> Void

    private let trackW: CGFloat = 40
    private let trackH: CGFloat = 20
    private let thumbW: CGFloat = 14
    private let thumbH: CGFloat = 12

    var body: some View {
        if isEnabled {
            Button(action: onToggle) { track }
                .buttonStyle(.plain)
                .animation(.easeInOut(duration: 0.12), value: isOn)
        } else {
            // 비활성: Button으로 감싸지 않아 탭이 부모로 전달된다
            track
                .opacity(0.45)
                .animation(.easeInOut(duration: 0.12), value: isOn)
        }
    }

    private var track: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            // 트랙
            Rectangle()
                .fill(isOn ? Color.pixelOrange.opacity(0.12) : Color.pixelSurface)
                .overlay(
                    Rectangle()
                        .stroke(isOn ? Color.pixelOrange : Color.pixelBorder, lineWidth: 1.5)
                )
                .frame(width: trackW, height: trackH)

            // 썸
            Rectangle()
                .fill(isOn ? Color.pixelOrange : Color.pixelMuted.opacity(0.6))
                .frame(width: thumbW, height: thumbH)
                .padding(.horizontal, 2)
        }
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
                    .font(pixelFont(15))
                    .foregroundStyle(Color.pixelOrange)
                    .padding(.horizontal, 18)
                    .padding(.top, 13)
                    .padding(.bottom, 12)

                Rectangle()
                    .fill(Color.pixelBorder)
                    .frame(height: 1)
                    .padding(.horizontal, 18)

                // 메시지
                Text(message)
                    .font(pixelFont(11))
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
                        .font(pixelFont(12))
                        .foregroundStyle(Color.pixelOrange)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
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

// MARK: - PixelConfirm (예/아니오 2버튼 확인 다이얼로그)

struct PixelConfirm: View {
    let title: String
    let message: String
    let confirmTitle: String
    let cancelTitle: String
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                Text(title.uppercased())
                    .font(pixelFont(15))
                    .foregroundStyle(Color.pixelOrange)
                    .padding(.horizontal, 18)
                    .padding(.top, 13)
                    .padding(.bottom, 12)

                Rectangle()
                    .fill(Color.pixelBorder)
                    .frame(height: 1)
                    .padding(.horizontal, 18)

                Text(message)
                    .font(pixelFont(11))
                    .foregroundStyle(Color.pixelText)
                    .lineSpacing(5)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)

                Rectangle()
                    .fill(Color.pixelBorder)
                    .frame(height: 1)
                    .padding(.horizontal, 18)

                HStack(spacing: 0) {
                    Button(action: onCancel) {
                        Text(cancelTitle.uppercased())
                            .font(pixelFont(12))
                            .foregroundStyle(Color.pixelMuted)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                    }
                    .buttonStyle(.plain)

                    Rectangle()
                        .fill(Color.pixelBorder)
                        .frame(width: 1, height: 40)

                    Button(action: onConfirm) {
                        Text("> \(confirmTitle.uppercased())_")
                            .font(pixelFont(12))
                            .foregroundStyle(Color.pixelOrange)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                    }
                    .buttonStyle(.plain)
                }
            }
            .pixelBox(border: Color.pixelBorder, bg: Color.pixelSurface, lineWidth: 1.5, notch: 8)
            .padding(.horizontal, 40)
        }
    }
}

extension View {
    func pixelConfirm(
        title: String,
        message: String,
        confirmTitle: String = "추가",
        cancelTitle: String = "취소",
        isPresented: Binding<Bool>,
        onConfirm: @escaping () -> Void = {}
    ) -> some View {
        ZStack {
            self
            if isPresented.wrappedValue {
                PixelConfirm(
                    title: title,
                    message: message,
                    confirmTitle: confirmTitle,
                    cancelTitle: cancelTitle,
                    onConfirm: {
                        onConfirm()
                        isPresented.wrappedValue = false
                    },
                    onCancel: { isPresented.wrappedValue = false }
                )
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

#Preview("pixel toggle") {
    
    ZStack {
        Color.bg
            .ignoresSafeArea()
        
        VStack {
            PixelToggle(isOn: true, onToggle: {})
            PixelToggle(isOn: false, onToggle: {})

        }
    }
    
        
    
    
}
