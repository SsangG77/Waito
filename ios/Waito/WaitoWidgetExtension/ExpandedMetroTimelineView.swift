import SwiftUI

struct ExpandedMetroTimelineView: View {
    let state: DeliveryAttributes.ContentState
    @State private var isPulsing = false

    private let allStatuses = DeliveryStatus.allCases

    var body: some View {
        Group {
            if let primary = state.primary {
                mainContent(primary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.black)
        .onAppear { isPulsing = true }
    }

    private func mainContent(_ item: TrackingItemState) -> some View {
        VStack(spacing: 5) {
            HStack {
                Text(item.itemName)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer()
                Text(item.status.isCompleted ? "배송완료 ✓" : (item.estimatedDelivery ?? ""))
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.wPixelGreen)
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
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.wPixelOrange)
                Spacer()
                Text("\(item.status.order + 1)/7 완료")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
    }

    private func trackSection(current: DeliveryStatus, config: TruckConfig) -> some View {
        let currentOrder = current.order
        let count = allStatuses.count

        return VStack(spacing: 3) {
            // Truck row — positioned above active dot
            GeometryReader { geo in
                let spacing = geo.size.width / CGFloat(count - 1)
                CatalogTruckView(cab: config.cab, truckBody: config.body, wheels: config.wheelType, size: 11)
                    .frame(width: 15)
                    .position(x: spacing * CGFloat(currentOrder), y: 7)
                    .animation(.spring(duration: 0.8), value: currentOrder)
            }
            .frame(height: 14)

            // Track: dots + lines via Canvas + pulse overlay
            ZStack {
                Canvas { ctx, size in
                    let spacing = size.width / CGFloat(count - 1)
                    let dotR: CGFloat = 4
                    let midY = size.height / 2

                    for i in 0..<(count - 1) {
                        let x1 = spacing * CGFloat(i) + dotR + 1
                        let x2 = spacing * CGFloat(i + 1) - dotR - 1
                        let linePath = Path { p in
                            p.move(to: CGPoint(x: x1, y: midY))
                            p.addLine(to: CGPoint(x: x2, y: midY))
                        }
                        let lineColor: Color = i < currentOrder ? .white.opacity(0.6) : .white.opacity(0.12)
                        ctx.stroke(linePath, with: .color(lineColor), lineWidth: 1.5)
                    }

                    for i in 0..<count {
                        let x = spacing * CGFloat(i)
                        let rect = CGRect(x: x - dotR, y: midY - dotR, width: dotR * 2, height: dotR * 2)
                        let dotPath = Path(ellipseIn: rect)
                        if i < currentOrder {
                            ctx.fill(dotPath, with: .color(.white))
                        } else if i == currentOrder {
                            ctx.fill(dotPath, with: .color(.wPixelOrange))
                        } else {
                            ctx.stroke(dotPath, with: .color(.white.opacity(0.2)), lineWidth: 1)
                        }
                    }
                }
                .frame(height: 16)

                // Pulse ring on active dot
                GeometryReader { geo in
                    let spacing = geo.size.width / CGFloat(count - 1)
                    let x = spacing * CGFloat(currentOrder)
                    Circle()
                        .fill(Color.wPixelOrange.opacity(isPulsing ? 0.0 : 0.35))
                        .frame(width: 16, height: 16)
                        .position(x: x, y: geo.size.height / 2)
                        .animation(
                            .easeInOut(duration: 1.3).repeatForever(autoreverses: true),
                            value: isPulsing
                        )
                }
                .frame(height: 16)
            }

            // Labels
            GeometryReader { geo in
                let spacing = geo.size.width / CGFloat(count - 1)
                ForEach(Array(allStatuses.enumerated()), id: \.element) { idx, status in
                    Text(status.metroLabel)
                        .font(.system(size: 5.5))
                        .foregroundStyle(status == current ? Color.wPixelOrange : Color.white.opacity(0.25))
                        .frame(width: 22, alignment: .center)
                        .position(x: spacing * CGFloat(idx), y: 5)
                }
            }
            .frame(height: 10)
        }
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
