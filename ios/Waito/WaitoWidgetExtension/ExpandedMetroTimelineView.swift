import SwiftUI

struct ExpandedMetroTimelineView: View {
    let state: DeliveryAttributes.ContentState

    var body: some View {
        Group {
            if let primary = state.primary {
                mainContent(primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
            } else {
                idleContent
            }
        }
        // 배경은 건드리지 않음 — DI 펼침은 시스템 기본 검정 유지
    }

    /// 배송이 없을 때(항상 노출) — 좌측 트럭 + 우측 BOUNCE 버튼만 (배경 없음)
    private var idleContent: some View {
        HStack(spacing: 10) {
            CatalogTruckView(cab: state.truckConfig.cab, truckBody: state.truckConfig.body, wheels: state.truckConfig.wheelType, size: 36)
                .offset(y: state.truckBounce ?? 0)
                .animation(nil, value: state.truckBounce ?? 0)   // 보간 없이 스냅 → 8비트풍 바운스
                .padding(.leading, 6)

            Button(intent: BounceTruckIntent()) {
                HStack(spacing: 8) {
                    Text(">")
                    Text("BOUNCE_")
                }
                .font(pixelFont(18))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .wPixelBox(border: Color.wPixelRed.opacity(0.7), bg: Color.wPixelRed, lineWidth: 2, notch: 4)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    /// center 영역 — 물품명(위) + 가변 타임라인(아래) 세로 배치.
    /// (출발 날짜·상태 라벨은 bottom 영역에서 표시)
    private func mainContent(_ item: TrackingItemState) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.itemName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)

            trackSection(current: item.status, config: state.truckConfig)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func trackSection(current: DeliveryStatus, config: TruckConfig) -> some View {
        // 전체 배송 과정(고정 단계)을 항상 표시 — 진행된 만큼 채우고 남은 단계는 흐리게.
        let count = DeliveryStatus.collapsedStages.count
        let currentOrder = current.collapsedStepIndex
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
