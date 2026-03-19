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
                    Label(context.state.carrierName, systemImage: "box.truck.fill")
                        .font(.caption2)
                        .foregroundStyle(.white)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if let eta = context.state.estimatedDelivery {
                        Text(eta)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ExpandedTruckPathView(state: context.state)
                }
            } compactLeading: {
                Image(systemName: "box.truck.fill")
                    .foregroundStyle(.white)
            } compactTrailing: {
                Text(context.state.status.displayName)
                    .font(.caption2)
                    .foregroundStyle(.white)
            } minimal: {
                Image(systemName: "box.truck.fill")
                    .foregroundStyle(.white)
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
        VStack(spacing: 8) {
            ZStack {
                // Layer 1-a: 전체 외곽선 (미완료 구간 — 회색)
                IslandOutlineShape(cornerRadius: cornerRadius)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1.5)

                // Layer 1-b: 진행 외곽선 (완료 구간 — 흰색)
                IslandOutlineShape(cornerRadius: cornerRadius)
                    .trim(from: 0, to: state.status.progress)
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 2, lineCap: .round))

                // Layer 2: 트럭 아이콘
                truckIcon
            }
            .frame(width: pathSize.width, height: pathSize.height)
            .padding(10) // 트럭 아이콘 오버플로우 여유

            // Layer 3: 상태 텍스트
            HStack(spacing: 4) {
                Text(state.status.displayName)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)

                if let eta = state.estimatedDelivery {
                    Text("·")
                        .foregroundStyle(.white.opacity(0.5))
                    Text(eta)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
    }

    private var truckIcon: some View {
        let pose = calculator.pose(at: state.status.progress)
        return Image(systemName: "box.truck.fill")
            .font(.system(size: 12))
            .foregroundStyle(.white)
            .rotationEffect(.radians(pose.rotationAngle))
            .position(x: pose.position.x, y: pose.position.y)
    }
}

// MARK: - Lock Screen / Banner View

struct LockScreenLiveActivityView: View {
    let state: DeliveryAttributes.ContentState

    var body: some View {
        HStack(spacing: 12) {
            // 트럭 아이콘
            Image(systemName: "box.truck.fill")
                .font(.title2)
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 4) {
                // 택배사 + 상태
                HStack {
                    Text(state.carrierName)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                    Spacer()
                    Text(state.status.displayName)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                }

                // 진행 바
                ProgressBarView(progress: state.status.progress)

                // 아이템명 + 도착 예정
                HStack {
                    Text(state.itemName)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.5))
                    Spacer()
                    if let eta = state.estimatedDelivery {
                        Text(eta)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
            }
        }
        .padding(16)
    }
}

// MARK: - Progress Bar (Lock Screen용)

struct ProgressBarView: View {
    let progress: CGFloat

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // 배경 트랙
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white.opacity(0.2))

                // 진행 트랙
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white)
                    .frame(width: geometry.size.width * progress)
            }
        }
        .frame(height: 4)
    }
}

// MARK: - Dynamic Island 외곽선 Shape

/// Dynamic Island 테두리를 하단 중앙에서 시작해 시계방향으로 그리는 커스텀 Shape
/// `.trim(from:to:)` 사용 시 t값 시스템과 일치하도록 설계
struct IslandOutlineShape: Shape {
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let r = min(cornerRadius, min(rect.width, rect.height) / 2)

        // 시작: 하단 중앙
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))

        // ← 하단 직선 (중앙 → 좌측)
        path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))

        // ↰ 좌하 코너 (90° → 180°)
        path.addArc(
            center: CGPoint(x: rect.minX + r, y: rect.maxY - r),
            radius: r,
            startAngle: .degrees(90),
            endAngle: .degrees(180),
            clockwise: false
        )

        // ↑ 좌측 직선
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))

        // ↰ 좌상 코너 (180° → 270°)
        path.addArc(
            center: CGPoint(x: rect.minX + r, y: rect.minY + r),
            radius: r,
            startAngle: .degrees(180),
            endAngle: .degrees(270),
            clockwise: false
        )

        // → 상단 직선
        path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))

        // ↰ 우상 코너 (270° → 360°)
        path.addArc(
            center: CGPoint(x: rect.maxX - r, y: rect.minY + r),
            radius: r,
            startAngle: .degrees(270),
            endAngle: .degrees(360),
            clockwise: false
        )

        // ↓ 우측 직선
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))

        // ↰ 우하 코너 (0° → 90°)
        path.addArc(
            center: CGPoint(x: rect.maxX - r, y: rect.maxY - r),
            radius: r,
            startAngle: .degrees(0),
            endAngle: .degrees(90),
            clockwise: false
        )

        // ← 하단 직선 (우측 → 중앙, 귀환)
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))

        return path
    }
}
