import SwiftUI

// MARK: - Compact Leading 바운싱 트럭

struct BouncingTruckView: View {
    let config: TruckConfig
    let size: CGFloat

    @State private var isUp = false

    var body: some View {
        CatalogTruckView(cab: config.cab, truckBody: config.body, wheels: config.wheelType, size: size)
            .offset(y: isUp ? -4 : 0)
            .animation(
                .easeInOut(duration: 0.45).repeatForever(autoreverses: true),
                value: isUp
            )
            .onAppear { isUp = true }
    }
}

// MARK: - 배송 없을 때(idle) 좌우로 왔다갔다 하는 트럭

/// 배송이 없는 항상 노출 상태에서 펼친 Dynamic Island / 잠금화면에 쓰는 순찰 트럭.
/// 위젯 프로세스는 타이머가 돌지 않으므로 선언형 repeatForever 애니메이션만 사용한다.
/// - offset: 좌우 왕복 이동(autoreverse)
/// - scaleEffect(x:): 진행 방향을 바라보도록 좌우 반전. period/2 만큼 위상을 늦춰
///   이동이 양 끝(벽)에 닿는 순간 트럭이 회전(반전)하도록 맞춘다.
struct RoamingTruckView: View {
    let config: TruckConfig
    var size: CGFloat = 28
    var travel: CGFloat = 100
    var period: Double = 1.8

    @State private var animate = false

    var body: some View {
        CatalogTruckView(cab: config.cab, truckBody: config.body, wheels: config.wheelType, size: size)
            .scaleEffect(x: animate ? -1 : 1, anchor: .center)
            .animation(
                .easeInOut(duration: period).delay(period / 2).repeatForever(autoreverses: true),
                value: animate
            )
            .offset(x: animate ? travel / 2 : -travel / 2)
            .animation(
                .easeInOut(duration: period).repeatForever(autoreverses: true),
                value: animate
            )
            .onAppear { animate = true }
    }
}

// MARK: - Compact Trailing 배송 진행 링

struct DeliveryProgressRingView: View {
    let progress: CGFloat
    let size: CGFloat
    /// 링을 이루는 픽셀 블록 개수 (둘레에 균등 배치)
    var segments: Int = 12

    var body: some View {
        // 매끈한 stroke 대신 작은 사각 블록을 둘레에 돌려 배치 → 8비트 픽셀 링.
        let filled = min(max(Int((progress * CGFloat(segments)).rounded()), 0), segments)
        let block = max(2.5, size * 0.2)
        let radius = size / 2 - block / 2

        ZStack {
            ForEach(0..<segments, id: \.self) { i in
                Rectangle()
                    .fill(i < filled ? Color.white : Color.white.opacity(0.2))
                    .frame(width: block, height: block)
                    .offset(y: -radius)
                    .rotationEffect(.degrees(Double(i) / Double(segments) * 360))
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Minimal 링 (다른 앱과 공존해 작은 원일 때) — 중앙 트럭 + 주변 얇은 진행 게이지

/// DI minimal 표시용. 얇은 원형 stroke 게이지(둘레) 안쪽 중앙에 트럭을 얹는다.
/// (compactLeading 의 픽셀 블록 링과 달리 좁은 원에 맞춰 매끈한 얇은 선으로 표현)
struct MinimalTruckRingView: View {
    let progress: CGFloat
    let config: TruckConfig
    var size: CGFloat = 22
    var lineWidth: CGFloat = 2

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.2), lineWidth: lineWidth)          // 남은 구간(트랙)
            Circle()
                .trim(from: 0, to: max(0, min(progress, 1)))
                .stroke(Color.white, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))                                    // 12시 시작, 시계방향
            CatalogTruckView(cab: config.cab, truckBody: config.body, wheels: config.wheelType, size: size * 0.6)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - 두 번째 택배 행 (Dynamic Island 하단)

struct SecondaryTrackingRow: View {
    let item: TrackingItemState

    var body: some View {
        HStack(spacing: 6) {
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
