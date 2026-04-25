import SwiftUI

#Preview {
    VStack(spacing: 0) {
        PixelNavBar(title: "SETTINGS", onBack: {})
        Spacer()
    }
    .background(Color.bg)
}

struct PixelNavBar: View {
    let title: String
    let onBack: () -> Void

    var body: some View {
        HStack {
            Button(action: onBack) {
                HStack(spacing: 5) {
                    Text("<")
                    Text("BACK")
                }
                .font(pixelFont(10))
                .foregroundStyle(Color.pixelText)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .pixelBox(border: Color.pixelBorder, bg: Color.pixelSurface, lineWidth: 1.5, notch: 3)
            }
            .buttonStyle(.plain)

            Spacer()

            Text(title)
                .font(pixelFont(12))
                .foregroundStyle(Color.pixelText)

            Spacer()

            // 좌우 대칭 더미
            HStack(spacing: 5) {
                Text("<")
                Text("BACK")
            }
            .font(pixelFont(10))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .opacity(0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.bg)
        .overlay(
            Rectangle()
                .fill(Color.pixelBorder)
                .frame(height: 1),
            alignment: .bottom
        )
    }
}
