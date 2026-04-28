import SwiftUI

// MARK: - Dynamic Island 외곽선 Shape (IslandOutlineShape 방식)

struct IslandOutlineShape: Shape {
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let r = min(cornerRadius, min(rect.width, rect.height) / 2)

        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        path.addArc(center: CGPoint(x: rect.minX + r, y: rect.maxY - r), radius: r,
                     startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        path.addArc(center: CGPoint(x: rect.minX + r, y: rect.minY + r), radius: r,
                     startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        path.addArc(center: CGPoint(x: rect.maxX - r, y: rect.minY + r), radius: r,
                     startAngle: .degrees(270), endAngle: .degrees(360), clockwise: false)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        path.addArc(center: CGPoint(x: rect.maxX - r, y: rect.maxY - r), radius: r,
                     startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))

        return path
    }
}

// MARK: - Expanded 트럭 경로 뷰 (IslandOutlineShape 기반)

struct ExpandedTruckPathView: View {
    let state: DeliveryAttributes.ContentState

    private let pathSize = CGSize(width: 250, height: 36.67)
    private let cornerRadius: CGFloat = 18.335
    private let calculator = TruckPathCalculator()

    private let progressLineOffset: CGFloat = 4
    private let truckOffset: CGFloat = 12
    private let animationPeriod: Double = 8.0

    var body: some View {
        VStack(spacing: 6) {
            if let primary = state.primary {
                ZStack {
                    IslandOutlineShape(cornerRadius: cornerRadius + progressLineOffset)
                        .stroke(Color.white.opacity(0.15), lineWidth: 1.5)

                    IslandOutlineShape(cornerRadius: cornerRadius + progressLineOffset)
                        .trim(from: 0, to: primary.status.progress)
                        .stroke(Color.white.opacity(0.9), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))

                    if state.truckConfig.runMode == .on {
                        TimelineView(.animation) { context in
                            truckIcon(t: animatedT(for: context.date), config: state.truckConfig)
                        }
                    } else {
                        truckIcon(t: primary.status.progress, config: state.truckConfig)
                            .animation(.spring(duration: 0.8), value: primary.status.progress)
                    }
                }
                .frame(width: pathSize.width + truckOffset * 2,
                       height: pathSize.height + truckOffset * 2)
                .padding(.horizontal, 2)
                .padding(.top, 6)

                HStack(spacing: 4) {
                    Text(primary.itemName)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text("·")
                        .foregroundStyle(.white.opacity(0.5))

                    Text(primary.status.displayName)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.8))

                    if let eta = primary.estimatedDelivery {
                        Text("·")
                            .foregroundStyle(.white.opacity(0.5))
                        Text(eta)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
            }
        }
    }

    private func animatedT(for date: Date) -> CGFloat {
        let elapsed = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: animationPeriod)
        let phase = elapsed / animationPeriod
        let pingPong = phase <= 0.5 ? phase * 2 : (1.0 - phase) * 2
        return CGFloat(pingPong * pingPong * (3.0 - 2.0 * pingPong))
    }

    private func truckIcon(t: CGFloat, config: TruckConfig) -> some View {
        let pose = calculator.pose(at: t, offset: truckOffset)
        return CatalogTruckView(cab: config.cab, truckBody: config.body, wheels: config.wheelType, size: 14)
            .rotationEffect(.radians(pose.rotationAngle))
            .position(
                x: pose.position.x + truckOffset,
                y: pose.position.y + truckOffset
            )
    }
}

// MARK: - Previews

private extension DeliveryAttributes.ContentState {
    static func previewState(status: DeliveryStatus, itemName: String = "맥북 프로 14인치") -> Self {
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

#Preview("C1 — 아일랜드 서킷 | 접수") {
    ExpandedTruckPathView(state: .previewState(status: .registered))
        .background(Color.black)
        .previewLayout(.sizeThatFits)
}

#Preview("C1 — 아일랜드 서킷 | 배송출발") {
    ExpandedTruckPathView(state: .previewState(status: .outForDelivery))
        .background(Color.black)
        .previewLayout(.sizeThatFits)
}

#Preview("C1 — 아일랜드 서킷 | 배송완료") {
    ExpandedTruckPathView(state: .previewState(status: .delivered))
        .background(Color.black)
        .previewLayout(.sizeThatFits)
}
