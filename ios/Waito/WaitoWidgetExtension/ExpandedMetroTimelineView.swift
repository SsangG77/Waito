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
//        .frame(height: 40)
    }

    /// center 영역 — 물품명(위) + 가변 타임라인(아래) 세로 배치.
    /// (출발 날짜·상태 라벨은 bottom 영역에서 표시)
    private func mainContent(_ item: TrackingItemState) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.itemName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)

            trackSection(current: item.status, eventCount: item.eventCount ?? 0, config: state.truckConfig)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func trackSection(current: DeliveryStatus, eventCount: Int, config: TruckConfig) -> some View {
        // 이벤트가 있으면 개수만큼(상한 내) 점, 전부 지나감, 트럭은 마지막 점. 없으면 status 7단계.
        let useEvents = eventCount > 0
        let maxDots = 14
        let count = useEvents ? min(eventCount, maxDots) : allStatuses.count
        let currentOrder = useEvents ? count - 1 : current.order
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

// MARK: - Previews

private extension DeliveryAttributes.ContentState {
    static func make(
        status: DeliveryStatus,
        itemName: String = "맥북 프로 14인치",
        eventCount: Int? = nil,
        statusLabel: String? = nil
    ) -> Self {
        .init(items: [
            TrackingItemState(
                trackingNumber: "123456789012",
                status: status,
                carrierName: "CJ대한통운",
                itemName: itemName,
                estimatedDelivery: "오늘 도착 예정",
                eventCount: eventCount,
                statusLabel: statusLabel
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

#Preview("C2 — 이벤트 가변 5개") {
    ExpandedMetroTimelineView(state: .make(status: .delivering, eventCount: 5, statusLabel: "옥천HUB 간선상차"))
        .frame(width: 320)
        .background(Color.black)
}

#Preview("C2 — 이벤트 가변 12개(긴 라벨)") {
    ExpandedMetroTimelineView(state: .make(status: .delivering, eventCount: 12, statusLabel: "서울 강남 집배점 도착 후 배송기사 인수"))
        .frame(width: 320)
        .background(Color.black)
}

#Preview("idle — 달리는 트럭") {
    ExpandedMetroTimelineView(state: .init(items: [], truckConfig: .default))
        .frame(width: 320)
        .background(Color.black)
}
