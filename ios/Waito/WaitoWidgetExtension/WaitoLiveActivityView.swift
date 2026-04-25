import SwiftUI
import WidgetKit
import ActivityKit

// MARK: - Live Activity Configuration

struct WaitoLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DeliveryAttributes.self) { context in
            // Lock Screen / Banner
            LockScreenLiveActivityView(state: context.state)
                .activityBackgroundTint(.black)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    if let primary = context.state.primary {
                        Label(primary.carrierName, systemImage: "box.truck.fill")
                            .font(.caption2)
                            .foregroundStyle(.white)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if let eta = context.state.primary?.estimatedDelivery {
                        Text(eta)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ExpandedTruckPathView(state: context.state)
                }
            } compactLeading: {
                BouncingTruckView(config: context.state.truckConfig, size: 24)
            } compactTrailing: {
                EmptyView()
            } minimal: {
                let cfg = context.state.truckConfig
                CatalogTruckView(cab: cfg.cab, truckBody: cfg.body, wheels: cfg.wheelType, size: 18)
            }
        }
    }
}

// MARK: - Dynamic Island Expanded View (착시 효과 핵심)
//
// 레이어 구조 (안쪽 → 바깥쪽):
//
//   1. Dynamic Island 하드웨어 (검정)
//   2. 진행률 선 — Island 바로 바깥 테두리
//      ━━━ 흰색 = 완료 구간
//      ─── 회색 = 미완료 구간
//   3. 트럭 — 진행률 선의 더 바깥
//      ON:  트럭이 진행률 무관하게 계속 달림 (꾸미기)
//      OFF: 트럭이 진행률 끝에 멈춤 (상태 표시)

struct ExpandedTruckPathView: View {
    let state: DeliveryAttributes.ContentState

    private let pathSize = CGSize(width: 250, height: 36.67)
    private let cornerRadius: CGFloat = 18.335
    private let calculator = TruckPathCalculator()

    /// 진행률 선의 바깥 오프셋 (Island → 선)
    private let progressLineOffset: CGFloat = 4
    /// 트럭의 바깥 오프셋 (Island → 트럭 중심)
    private let truckOffset: CGFloat = 12

    /// ON 모드 왕복 주기 (초): 4초 전진 + 4초 후진
    private let animationPeriod: Double = 8.0

    var body: some View {
        VStack(spacing: 6) {
            if let primary = state.primary {
                ZStack {
                    // Layer 1-a: 전체 외곽선 — 미완료 구간 (회색, 바깥 오프셋)
                    IslandOutlineShape(cornerRadius: cornerRadius + progressLineOffset)
                        .stroke(Color.white.opacity(0.15), lineWidth: 1.5)

                    // Layer 1-b: 진행 외곽선 — 완료 구간 (흰색, 바깥 오프셋)
                    IslandOutlineShape(cornerRadius: cornerRadius + progressLineOffset)
                        .trim(from: 0, to: primary.status.progress)
                        .stroke(Color.white.opacity(0.9), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))

                    // Layer 2: 트럭 아이콘
                    // ON 모드: TimelineView로 시간 기반 연속 애니메이션
                    // OFF 모드: 배송 단계 t값 위치에 고정
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

                // 상태 텍스트 (주 택배)
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

    // MARK: - 시간 기반 T값 계산 (0→1→0 easeInOut 반복)

    private func animatedT(for date: Date) -> CGFloat {
        let elapsed = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: animationPeriod)
        let phase = elapsed / animationPeriod // 0.0~1.0 선형
        // 전반부 0→0.5: t 0→1, 후반부 0.5→1: t 1→0 (오토리버스)
        let pingPong = phase <= 0.5 ? phase * 2 : (1.0 - phase) * 2
        // smoothstep으로 easeInOut 적용
        return CGFloat(pingPong * pingPong * (3.0 - 2.0 * pingPong))
    }

    // MARK: - 트럭 렌더링

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

// MARK: - 두 번째 택배 행 (Dynamic Island 하단)

struct SecondaryTrackingRow: View {
    let item: TrackingItemState

    var body: some View {
        HStack(spacing: 6) {
            // 미니 프로그레스
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

// MARK: - Compact Leading 바운싱 트럭

struct BouncingTruckView: View {
    let config: TruckConfig
    let size: CGFloat

    private let period: Double = 1.0  // 1초 1사이클

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
                        .truncatingRemainder(dividingBy: period) / period
            // abs(sin) → 바닥에서 튀어오르는 자연스러운 곡선
            let offsetY = -abs(sin(t * .pi)) * 4

            CatalogTruckView(cab: config.cab, truckBody: config.body, wheels: config.wheelType, size: size)
                .offset(y: offsetY)
        }
    }
}

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

                LockScreenTrackingRow(item: secondary, truckConfig: state.truckConfig, showTruck: false)
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
                // 택배사 + 상태
                HStack {
                    Text(item.carrierName)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                    Spacer()
                    Text(item.status.displayName)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                }

                // 진행 바
                ProgressBarView(progress: item.status.progress)

                // 아이템명 + 도착 예정
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
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Progress Bar (Lock Screen용)

struct ProgressBarView: View {
    let progress: CGFloat

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white.opacity(0.2))
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white)
                    .frame(width: geometry.size.width * progress)
            }
        }
        .frame(height: 4)
    }
}

// MARK: - Dynamic Island 외곽선 Shape

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
