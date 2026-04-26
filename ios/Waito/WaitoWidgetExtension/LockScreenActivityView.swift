import SwiftUI

// MARK: - Lock Screen / Banner View

struct LockScreenLiveActivityView: View {
    let state: DeliveryAttributes.ContentState

    var body: some View {
        VStack(spacing: 0) {
            if let primary = state.primary {
                LockScreenTrackingRow(item: primary, truckConfig: state.truckConfig, showTruck: true)
            }

            if let secondary = state.secondary {
                Divider()
                    .background(Color.white.opacity(0.15))
                    .padding(.horizontal, 16)

                LockScreenTrackingRow(item: secondary, truckConfig: state.truckConfig, showTruck: true)
            }
        }
    }
}

// MARK: - 잠금화면 택배 행

struct LockScreenTrackingRow: View {
    let item: TrackingItemState
    let truckConfig: TruckConfig
    let showTruck: Bool

    var body: some View {
        HStack(spacing: 12) {
            if showTruck {
                CatalogTruckView(cab: truckConfig.cab, truckBody: truckConfig.body, wheels: truckConfig.wheelType, size: 36)
            } else {
                Image(systemName: "shippingbox.fill")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(width: 36, height: 36)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(item.itemName)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                    Spacer()
                    if let eta = item.estimatedDelivery {
                        Text(eta)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }

                ProgressBarView(status: item.status)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Progress Bar (Lock Screen용) — 픽셀 점+선

struct ProgressBarView: View {
    let status: DeliveryStatus

    private let steps = 7
    private let dotSize: CGFloat = 4
    private let gap: CGFloat = 3

    var body: some View {
        GeometryReader { geo in
            let lineWidth = max(0, (geo.size.width - (dotSize + gap * 2) * CGFloat(steps) + gap * 2) / CGFloat(steps - 1))

            ZStack(alignment: .leading) {
                ForEach(0..<steps - 1, id: \.self) { i in
                    let x = (dotSize + gap * 2 + lineWidth) * CGFloat(i) + dotSize + gap
                    let filled = status.isCompleted || CGFloat(i + 1) / CGFloat(steps) <= status.progress
                    Rectangle()
                        .fill(filled ? wPixelStatusColor(status) : Color.wPixelBorder)
                        .frame(width: lineWidth, height: 1)
                        .offset(x: x, y: dotSize / 2 - 0.5)
                }
                ForEach(0..<steps, id: \.self) { i in
                    let x = (dotSize + gap * 2 + lineWidth) * CGFloat(i)
                    let filled = status.isCompleted || CGFloat(i) / CGFloat(steps) < status.progress
                    Rectangle()
                        .fill(filled ? wPixelStatusColor(status) : Color.wPixelBorder)
                        .frame(width: dotSize, height: dotSize)
                        .offset(x: x)
                }
            }
        }
        .frame(height: dotSize)
    }
}
