import SwiftUI

// MARK: - Compact Leading 바운싱 트럭

struct BouncingTruckView: View {
    let config: TruckConfig
    let size: CGFloat

    @State private var isUp = false

    var body: some View {
        CatalogTruckView(cab: config.cab, truckBody: config.body, wheels: config.wheelType, size: size)
            .offset(y: isUp ? -4 : 0)
            .animation(
                .easeInOut(duration: 0.45).repeatForever(autoreverses: true),
                value: isUp
            )
            .onAppear { isUp = true }
    }
}

// MARK: - Compact Trailing 배송 진행 링

struct DeliveryProgressRingView: View {
    let progress: CGFloat
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.2), lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Color.white, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
    }
}

// MARK: - 두 번째 택배 행 (Dynamic Island 하단)

struct SecondaryTrackingRow: View {
    let item: TrackingItemState

    var body: some View {
        HStack(spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color.white.opacity(0.15))
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color.white.opacity(0.6))
                        .frame(width: geo.size.width * item.status.progress)
                }
            }
            .frame(width: 30, height: 3)

            Text(item.itemName)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(1)

            Spacer()

            Text(item.status.displayName)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding(.horizontal, 10)
    }
}
