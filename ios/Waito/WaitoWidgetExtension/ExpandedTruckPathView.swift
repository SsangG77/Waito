import SwiftUI
import WidgetKit
import ActivityKit

// MARK: - Dynamic Island 외곽선 Shape

/// 시계방향(iOS y-down 좌표계 기준)으로 좌상단에서 시작하는 라운드 사각형 path.
/// `TruckPathCalculator`의 t=0 위치/방향과 일치하도록 트레이스 순서가 맞춰져 있음.
struct IslandOutlineShape: Shape {
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let r = min(cornerRadius, min(rect.width, rect.height) / 2)

        // t=0 시작점 = 좌상 코너 끝 = 상단 직선 시작
        path.move(to: CGPoint(x: rect.minX + r, y: rect.minY))

        // ① 상단 직선: 좌 → 우
        path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))

        // ② 우상 코너 (270° → 360°)
        path.addArc(center: CGPoint(x: rect.maxX - r, y: rect.minY + r), radius: r,
                     startAngle: .degrees(270), endAngle: .degrees(360), clockwise: false)

        // ③ 우측 직선: 상 → 하
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))

        // ④ 우하 코너 (0° → 90°)
        path.addArc(center: CGPoint(x: rect.maxX - r, y: rect.maxY - r), radius: r,
                     startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)

        // ⑤ 하단 직선: 우 → 좌
        path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))

        // ⑥ 좌하 코너 (90° → 180°)
        path.addArc(center: CGPoint(x: rect.minX + r, y: rect.maxY - r), radius: r,
                     startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)

        // ⑦ 좌측 직선: 하 → 상
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))

        // ⑧ 좌상 코너 (180° → 270°)
        path.addArc(center: CGPoint(x: rect.minX + r, y: rect.minY + r), radius: r,
                     startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)

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

    // 시스템이 그리는 Expanded BIG SHAPE의 안쪽 테두리에 트럭이 거의 붙어 돌도록.
    // - 높이는 충분히 확보 (BIG SHAPE 자체를 크게 유지)
    // - 외곽선은 BIG SHAPE의 둥근 코너 곡률 안쪽에 들어가도록 strokeInset + cornerRadius 매칭
    private let strokeInset:    CGFloat = 0     // BIG SHAPE 둥근 코너 곡선 안으로 들어가는 여유
    private let truckInsetFromStroke: CGFloat = 10
    private let pathCornerRadius: CGFloat = 32  // BIG SHAPE 코너(~40) 보다 약간 작게
    private let truckSize:      CGFloat = 18
    private let animationPeriod: Double = 8.0

    var body: some View {
        if let primary = state.primary {
            GeometryReader { geo in
                circuit(in: geo.size, primary: primary)
            }
            // BIG SHAPE 크게 유지 → 트럭이 도는 외곽이 펼쳐진 다이나믹 아일랜드와 비슷한 크기.
            // .bottom 가용 영역을 최대한 차지하되, 시스템 라운드 클리핑 영역은
            // strokeInset(상하 8pt)으로 회피.
            .frame(minHeight: 100, maxHeight: 130)
            .padding(.top, 5)
        } else {
            // 배송 없음(항상 노출) — 이 뷰가 Expanded 에 연결될 경우 대비한 대기 표시
            HStack(spacing: 8) {
                CatalogTruckView(
                    cab: state.truckConfig.cab,
                    truckBody: state.truckConfig.body,
                    wheels: state.truckConfig.wheelType,
                    size: 16
                )
                .frame(width: 22)
                Text("배송 대기 중")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
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
        if pathSize.width < 30 || pathSize.height < 30 {
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
        .frame(width: pathSize.width + 6, height: pathSize.height + 5)
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
        // 트럭이 외곽선 안쪽에 있으므로 상하 반전 → 바퀴가 외곽선(바깥) 쪽을 향함.
        // (rotationEffect보다 먼저 적용 → 회전된 후에도 바퀴는 항상 외곽선 쪽)
        .scaleEffect(y: -1)
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
