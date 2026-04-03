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
                MiniTruckView(config: context.state.truckConfig, size: 24)
            } compactTrailing: {
                if let primary = context.state.primary {
                    Text(primary.status.displayName)
                        .font(.caption2)
                        .foregroundStyle(.white)
                }
            } minimal: {
                MiniTruckView(config: context.state.truckConfig, size: 18)
            }
        }
    }
}

// MARK: - Dynamic Island Expanded View (착시 효과 핵심)

struct ExpandedTruckPathView: View {
    let state: DeliveryAttributes.ContentState

    private let pathSize = CGSize(width: 250, height: 36.67)
    private let cornerRadius: CGFloat = 18.335
    private let calculator = TruckPathCalculator()

    var body: some View {
        VStack(spacing: 6) {
            if let primary = state.primary {
                ZStack {
                    // Layer 1-a: 전체 외곽선 (미완료 구간 — 회색)
                    IslandOutlineShape(cornerRadius: cornerRadius)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1.5)

                    // Layer 1-b: 진행 외곽선 (완료 구간 — 흰색)
                    IslandOutlineShape(cornerRadius: cornerRadius)
                        .trim(from: 0, to: primary.status.progress)
                        .stroke(Color.white, style: StrokeStyle(lineWidth: 2, lineCap: .round))

                    // Layer 2: 트럭 아이콘
                    truckIcon(for: primary)
                }
                .frame(width: pathSize.width, height: pathSize.height)
                .padding(10)

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

                // Dynamic Island에서는 첫 번째 택배만 표시
            }
        }
    }

    private func truckIcon(for item: TrackingItemState) -> some View {
        let pose = calculator.pose(at: item.status.progress)
        return MiniTruckView(config: state.truckConfig, size: 14)
            .rotationEffect(.radians(pose.rotationAngle))
            .position(x: pose.position.x, y: pose.position.y)
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
                MiniTruckView(config: truckConfig, size: 36)
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
