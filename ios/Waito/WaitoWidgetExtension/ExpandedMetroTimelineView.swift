import SwiftUI

struct ExpandedMetroTimelineView: View {
    let state: DeliveryAttributes.ContentState

    private let allStatuses = DeliveryStatus.allCases

    var body: some View {
        Group {
            if let primary = state.primary {
                mainContent(primary)
            } else {
                idleContent
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.black)
    }

    /// 배송이 없을 때(항상 노출) — 트럭만 표시
    private var idleContent: some View {
        CatalogTruckView(
            cab: state.truckConfig.cab,
            truckBody: state.truckConfig.body,
            wheels: state.truckConfig.wheelType,
            size: 26
        )
        .frame(maxWidth: .infinity, alignment: .center)
        .frame(height: 30)
    }

    private func mainContent(_ item: TrackingItemState) -> some View {
        VStack(spacing: 5) {
            HStack {
                Text(item.itemName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer()
                Text(item.status.isCompleted ? "배송완료 ✓" : (item.estimatedDelivery ?? ""))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.wPixelGreen)
            }

            trackSection(current: item.status, config: state.truckConfig)

            HStack {
                CatalogTruckView(
                    cab: state.truckConfig.cab,
                    truckBody: state.truckConfig.body,
                    wheels: state.truckConfig.wheelType,
                    size: 11
                )
                .frame(width: 15)
                
                Text(item.status.displayName)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.wPixelOrange)
                Spacer()
//                Text("\(item.status.order + 1)/7 완료")
//                    .font(.system(size: 9))
//                    .foregroundStyle(.white.opacity(0.4))
            }
        }
    }

    private func trackSection(current: DeliveryStatus, config: TruckConfig) -> some View {
        let currentOrder = current.order
        let count = allStatuses.count
        let dotSize: CGFloat = 5
        let gap: CGFloat = 4

        return VStack(spacing: 3) {
            // Truck row — positioned above active dot center
            GeometryReader { geo in
                let unit = unitWidth(total: geo.size.width, count: count, dotSize: dotSize, gap: gap)
                let xCenter = unit * CGFloat(currentOrder) + dotSize / 2
                CatalogTruckView(cab: config.cab, truckBody: config.body, wheels: config.wheelType, size: 13)
                    .frame(width: 15)
                    .position(x: xCenter, y: 7)
                    .animation(.spring(duration: 0.8), value: currentOrder)
            }
            .frame(height: 14)

            // Pixel stepper bar — 사각 점 + 가는 선, 양쪽에 gap
            GeometryReader { geo in
                let total = geo.size.width
                let unit = unitWidth(total: total, count: count, dotSize: dotSize, gap: gap)
                let lineW = max(0, unit - dotSize - gap * 2)

                ZStack(alignment: .leading) {
                    // Lines
                    ForEach(0..<count - 1, id: \.self) { i in
                        let x = unit * CGFloat(i) + dotSize + gap
                        let filled = i < currentOrder
                        Rectangle()
                            .fill(filled ? Color.wPixelOrange.opacity(0.7) : Color.white.opacity(0.15))
                            .frame(width: lineW, height: 1)
                            .offset(x: x, y: dotSize / 2 - 0.5)
                    }
                    // Dots
                    ForEach(0..<count, id: \.self) { i in
                        let x = unit * CGFloat(i)
                        Rectangle()
                            .fill(dotColor(index: i, currentOrder: currentOrder))
                            .frame(width: dotSize, height: dotSize)
                            .offset(x: x)
                    }
                }
            }
            .frame(height: dotSize)

            // Labels — 각 점 중심에 정렬
            GeometryReader { geo in
                let unit = unitWidth(total: geo.size.width, count: count, dotSize: dotSize, gap: gap)
                ForEach(Array(allStatuses.enumerated()), id: \.element) { idx, status in
                    Text(status.metroLabel)
                        .font(.system(size: 7.7))
                        .foregroundStyle(status == current ? Color.wPixelOrange : Color.white.opacity(0.25))
                        .frame(width: 22, alignment: .center)
                        .position(x: unit * CGFloat(idx) + dotSize / 2, y: 5)
                }
            }
            .frame(height: 10)
        }
    }

    private func unitWidth(total: CGFloat, count: Int, dotSize: CGFloat, gap: CGFloat) -> CGFloat {
        guard count > 1 else { return total }
        return (total - dotSize) / CGFloat(count - 1)
    }

    private func dotColor(index: Int, currentOrder: Int) -> Color {
        if index < currentOrder { return Color.wPixelOrange.opacity(0.7) }
        if index == currentOrder { return Color.wPixelOrange }
        return Color.white.opacity(0.2)
    }
}

private extension DeliveryStatus {
    var metroLabel: String {
        switch self {
        case .registered:     return "접수"
        case .pickedUp:       return "집화"
        case .inTransitIn:    return "상차"
        case .inTransitOut:   return "하차"
        case .outForDelivery: return "출발"
        case .delivering:     return "배송중"
        case .delivered:      return "완료"
        }
    }
}

// MARK: - Previews

private extension DeliveryAttributes.ContentState {
    static func make(status: DeliveryStatus, itemName: String = "맥북 프로 14인치") -> Self {
        .init(items: [
            TrackingItemState(
                trackingNumber: "123456789012",
                status: status,
                carrierName: "CJ대한통운",
                itemName: itemName,
                estimatedDelivery: "오늘 도착 예정"
            )
        ], truckConfig: .default)
    }
}

#Preview("C2 — 메트로 타임라인 | 접수") {
    ExpandedMetroTimelineView(state: .make(status: .registered))
        .frame(width: 320)
        .background(Color.black)
}

#Preview("C2 — 메트로 타임라인 | 배송출발") {
    ExpandedMetroTimelineView(state: .make(status: .outForDelivery))
        .frame(width: 320)
        .background(Color.black)
}

#Preview("C2 — 메트로 타임라인 | 배송완료") {
    ExpandedMetroTimelineView(state: .make(status: .delivered))
        .frame(width: 320)
        .background(Color.black)
}

#Preview("idle — 달리는 트럭") {
    ExpandedMetroTimelineView(state: .init(items: [], truckConfig: .default))
        .frame(width: 320)
        .background(Color.black)
}
