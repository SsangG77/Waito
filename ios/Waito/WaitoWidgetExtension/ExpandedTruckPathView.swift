import SwiftUI
import WidgetKit
import ActivityKit

// MARK: - Dynamic Island 외곽선 Shape

/// 시계방향(iOS y-down 좌표계 기준)으로 하단 중앙에서 시작하는 라운드 사각형 path.
/// `TruckPathCalculator`의 t=0 위치/방향과 일치하도록 트레이스 순서가 맞춰져 있음.
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

// MARK: - Expanded 트럭 경로 뷰 (Island Circuit — Expanded 영역 풀 채우기)

/// Dynamic Island Expanded `.bottom` 영역 전체를 채우고, 그 안쪽 테두리를 따라
/// 트럭이 시계방향으로 달리면서 진행률을 시각화.
///
/// 카메라 하드웨어 테두리 위를 도는 착시는 시스템 제약으로 불가능하므로,
/// 펼쳐진 영역 자체의 안쪽 테두리를 트랙으로 사용 (=하드웨어 아래에서 한 바퀴).
struct ExpandedTruckPathView: View {
    let state: DeliveryAttributes.ContentState

    // 펼쳐진 DI 외곽 알약 안쪽에 트럭이 거의 붙어서 도는 느낌.
    // strokeInset 작게 → 알약 외곽이 system이 그리는 expanded DI 외곽과 시각적으로 일치.
    private let strokeInset:    CGFloat = 2
    private let truckInsetFromStroke: CGFloat = 10
    private let pathCornerRadius: CGFloat = 36
    private let truckSize:      CGFloat = 18
    private let animationPeriod: Double = 8.0

    var body: some View {
        if let primary = state.primary {
            GeometryReader { geo in
                circuit(in: geo.size, primary: primary)
            }
            .frame(minHeight: 130)
        }
    }

    @ViewBuilder
    private func circuit(in outerSize: CGSize, primary: TrackingItemState) -> some View {
        let pathSize = CGSize(
            width:  max(outerSize.width  - strokeInset * 2, 0),
            height: max(outerSize.height - strokeInset * 2, 0)
        )

        // 초기 레이아웃 패스에서 GeometryReader가 0×0을 반환하면
        // TruckPathCalculator에서 NaN 발생 → SwiftUI 레이아웃 무한 루프 위험.
        // 충분한 크기가 확보되기 전엔 빈 뷰 반환.
        if pathSize.width < 40 || pathSize.height < 40 {
            Color.clear
        } else {
            let r = min(pathCornerRadius, min(pathSize.width, pathSize.height) / 2)
            let calculator = TruckPathCalculator(metrics: .init(
                rect: CGRect(origin: .zero, size: pathSize),
                cornerRadius: r
            ))
            circuitContent(
                primary: primary,
                pathSize: pathSize,
                outerSize: outerSize,
                cornerRadius: r,
                calculator: calculator
            )
        }
    }

    private func circuitContent(
        primary: TrackingItemState,
        pathSize: CGSize,
        outerSize: CGSize,
        cornerRadius r: CGFloat,
        calculator: TruckPathCalculator
    ) -> some View {
        ZStack {
            IslandOutlineShape(cornerRadius: r)
                .stroke(Color.white.opacity(0.1), lineWidth: 2)

            IslandOutlineShape(cornerRadius: r)
                .trim(from: 0, to: primary.status.progress)
                .stroke(
                    Color.white.opacity(0.9),
                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                )
                .animation(.spring(duration: 0.8), value: primary.status.progress)

            centerContent(primary: primary)

            if state.truckConfig.runMode == .on {
                TimelineView(.animation) { context in
                    truckIcon(
                        t: animatedT(for: context.date),
                        config: state.truckConfig,
                        calculator: calculator
                    )
                }
            } else {
                truckIcon(
                    t: primary.status.progress,
                    config: state.truckConfig,
                    calculator: calculator
                )
                .animation(.spring(duration: 0.8), value: primary.status.progress)
            }
        }
        .frame(width: pathSize.width, height: pathSize.height)
        .position(x: outerSize.width / 2, y: outerSize.height / 2)
    }

    private func centerContent(primary: TrackingItemState) -> some View {
        VStack(spacing: 2) {
            Text(primary.itemName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
            Text(primary.status.displayName)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.6))
            if let eta = primary.estimatedDelivery {
                Text(eta)
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.35))
            }
        }
        .padding(.horizontal, 40)
        .multilineTextAlignment(.center)
    }

    private func truckIcon(t: CGFloat, config: TruckConfig, calculator: TruckPathCalculator) -> some View {
        let pose = calculator.pose(at: t, offset: -truckInsetFromStroke)
        return CatalogTruckView(
            cab: config.cab,
            truckBody: config.body,
            wheels: config.wheelType,
            size: truckSize
        )
        .rotationEffect(.radians(pose.rotationAngle))
        .position(x: pose.position.x, y: pose.position.y)
    }

    private func animatedT(for date: Date) -> CGFloat {
        let elapsed = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: animationPeriod)
        let phase = elapsed / animationPeriod
        let pingPong = phase <= 0.5 ? phase * 2 : (1.0 - phase) * 2
        return CGFloat(pingPong * pingPong * (3.0 - 2.0 * pingPong))
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

private let _truckPathPreviewAttr = DeliveryAttributes(deviceId: "preview")

#Preview("C1 — 아일랜드 서킷 (Expanded)",
         as: .dynamicIsland(.expanded),
         using: _truckPathPreviewAttr) {
    WaitoLiveActivity()
} contentStates: {
    DeliveryAttributes.ContentState.previewState(status: .registered)
    DeliveryAttributes.ContentState.previewState(status: .outForDelivery)
    DeliveryAttributes.ContentState.previewState(status: .delivered)
}
