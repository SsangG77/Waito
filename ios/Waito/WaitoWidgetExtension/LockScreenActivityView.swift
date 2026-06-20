import SwiftUI
import AppIntents

// MARK: - Lock Screen / Banner View

struct LockScreenLiveActivityView: View {
    let state: DeliveryAttributes.ContentState

    var body: some View {
        VStack(spacing: 0) {
            if let primary = state.primary {
                LockScreenTrackingRow(item: primary, truckConfig: state.truckConfig)

                if let secondary = state.secondary {
                    Divider()
                        .background(Color.white.opacity(0.15))
                        .padding(.horizontal, 16)

                    LockScreenTrackingRow(item: secondary, truckConfig: state.truckConfig)
                }
            } else {
                // 배송 없음(항상 노출) — 잠금화면 카드는 최소 대기 상태로 표시
                LockScreenIdleRow(truckConfig: state.truckConfig, bounce: state.truckBounce ?? 0)
            }
        }
        .frame(maxWidth: .infinity)
        .background(Color("bg"))
    }
}

// MARK: - 잠금화면 대기(idle) 행 — 배송 없을 때 좌우로 왔다갔다 하는 트럭

struct LockScreenIdleRow: View {
    let truckConfig: TruckConfig
    /// 활동 시작 시 앱이 위/아래로 갱신하는 세로 오프셋 → 시스템 전환 애니메이션으로 바운스.
    var bounce: Double = 0

    var body: some View {
        // 배송 없을 때(항상 노출): 왼쪽 끝 트럭 아이콘 + 나머지 공간에 "Waito" 크게.
        // 카드 세로 전체를 차지해 배경색(bg)이 위아래 끝까지 덮이게 한다.
        HStack(spacing: 10) {
            CatalogTruckView(cab: truckConfig.cab, truckBody: truckConfig.body, wheels: truckConfig.wheelType, size: 40)
                .offset(y: bounce)
                .animation(nil, value: bounce)   // 보간 없이 스냅 → 8비트 게임처럼 끊기는 바운스

            // 누르면 BounceTruckIntent 실행 → 트럭이 위아래로 바운스
            Button(intent: BounceTruckIntent()) {
                Text("> BOUNCE")
                    .font(pixelFont(20))   // 공유 픽셀 폰트(Galmuri9)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.white.opacity(0.55), lineWidth: 1.5)
                    )
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - 잠금화면 택배 행

struct LockScreenTrackingRow: View {
    let item: TrackingItemState
    let truckConfig: TruckConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 상단: 물품명(왼쪽) · 상태 라벨(오른쪽, = 마지막 이벤트 원본 설명)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(item.itemName)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white.opacity(0.95))
                    .lineLimit(1)
                    .layoutPriority(1)   // 물품명 우선, 긴 상태 라벨이 먼저 truncate
                Spacer(minLength: 8)
                Text(item.statusLabel ?? item.status.displayName)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(wPixelStatusColor(item.status))
                    .lineLimit(1)
            }

            // 이벤트 개수 기반 가변 타임라인 + 마지막(현재) 점 위에 작은 트럭
            LockScreenStatusTimeline(status: item.status, eventCount: item.eventCount ?? 0, truckConfig: truckConfig)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - 상태 타임라인(점+선) + 현재 상태 점 위 트럭

struct LockScreenStatusTimeline: View {
    let status: DeliveryStatus
    /// 원본 이벤트 개수(가변). 0이면 status 기반 7단계로 폴백.
    let eventCount: Int
    let truckConfig: TruckConfig

    private let dotSize: CGFloat = 5
    private let gap: CGFloat = 3
    private let truckSize: CGFloat = 16
    private let truckGap: CGFloat = 3   // 트럭과 점 사이 세로 간격
    private let maxDots = 14            // 잠금화면 폭 상한 (과다 이벤트 시 점 붕괴 방지)

    var body: some View {
        // 이벤트가 있으면 개수만큼(상한 내) 점, 전부 지나감(채움), 트럭은 마지막 점.
        // 없으면(확인중/구버전 push) status 기반 7단계 폴백.
        let useEvents = eventCount > 0
        let count = useEvents ? min(eventCount, maxDots) : DeliveryStatus.allCases.count
        let currentIndex = useEvents ? count - 1 : status.order

        GeometryReader { geo in
            let denom = CGFloat(max(count - 1, 1))
            let lineWidth = max(0, (geo.size.width - (dotSize + gap * 2) * CGFloat(count) + gap * 2) / denom)
            let stepW = dotSize + gap * 2 + lineWidth
            let dotsCenterY = truckSize + truckGap + dotSize / 2
            let currentDotCenterX = stepW * CGFloat(currentIndex) + dotSize / 2
            let truckX = min(max(currentDotCenterX, truckSize / 2), geo.size.width - truckSize / 2)

            ZStack(alignment: .topLeading) {
                // 연결선
                if count > 1 {
                    ForEach(0..<count - 1, id: \.self) { i in
                        let x = stepW * CGFloat(i) + dotSize + gap
                        let filled = useEvents || status.isCompleted || i < status.order
                        Rectangle()
                            .fill(filled ? wPixelStatusColor(status) : Color.white.opacity(0.22))
                            .frame(width: lineWidth, height: 1)
                            .offset(x: x, y: dotsCenterY - 0.5)
                    }
                }
                // 점
                ForEach(0..<count, id: \.self) { i in
                    let x = stepW * CGFloat(i)
                    let filled = useEvents || status.isCompleted || i <= status.order
                    Rectangle()
                        .fill(filled ? wPixelStatusColor(status) : Color.white.opacity(0.25))
                        .frame(width: dotSize, height: dotSize)
                        .offset(x: x, y: dotsCenterY - dotSize / 2)
                }
                // 마지막(현재) 점 위 작은 트럭
                CatalogTruckView(cab: truckConfig.cab, truckBody: truckConfig.body, wheels: truckConfig.wheelType, size: truckSize)
                    .frame(width: truckSize, height: truckSize)
                    .position(x: truckX, y: truckSize / 2)
            }
        }
        .frame(height: truckSize + truckGap + dotSize)
    }
}

// MARK: - Progress Bar (Lock Screen용) — 픽셀 점+선

struct ProgressBarView: View {
    let status: DeliveryStatus

    private let steps = 7
    private let dotSize: CGFloat = 4
    private let gap: CGFloat = 3

    var body: some View {
        GeometryReader { geo in
            let lineWidth = max(0, (geo.size.width - (dotSize + gap * 2) * CGFloat(steps) + gap * 2) / CGFloat(steps - 1))

            ZStack(alignment: .leading) {
                ForEach(0..<steps - 1, id: \.self) { i in
                    let x = (dotSize + gap * 2 + lineWidth) * CGFloat(i) + dotSize + gap
                    let filled = status.isCompleted || CGFloat(i + 1) / CGFloat(steps) <= status.progress
                    Rectangle()
                        .fill(filled ? wPixelStatusColor(status) : Color.wPixelBorder)
                        .frame(width: lineWidth, height: 1)
                        .offset(x: x, y: dotSize / 2 - 0.5)
                }
                ForEach(0..<steps, id: \.self) { i in
                    let x = (dotSize + gap * 2 + lineWidth) * CGFloat(i)
                    let filled = status.isCompleted || CGFloat(i) / CGFloat(steps) < status.progress
                    Rectangle()
                        .fill(filled ? wPixelStatusColor(status) : Color.wPixelBorder)
                        .frame(width: dotSize, height: dotSize)
                        .offset(x: x)
                }
            }
        }
        .frame(height: dotSize)
    }
}

// MARK: - Previews

#Preview("잠금화면 — 이벤트 가변 6개") {
    LockScreenLiveActivityView(state: .init(
        items: [
            TrackingItemState(
                trackingNumber: "123456789012",
                status: .delivering,
                carrierName: "CJ대한통운",
                itemName: "맥북 프로 14인치",
                estimatedDelivery: "오늘 도착 예정",
                eventCount: 6,
                statusLabel: "옥천HUB 간선상차"
            )
        ],
        truckConfig: .default
    ))
    .background(Color.black)
}

#Preview("잠금화면 — 많은 이벤트 + 긴 라벨") {
    LockScreenLiveActivityView(state: .init(
        items: [
            TrackingItemState(
                trackingNumber: "123456789012",
                status: .delivering,
                carrierName: "CJ대한통운",
                itemName: "에어팟 프로 2세대 USB-C",
                estimatedDelivery: "오늘 도착 예정",
                eventCount: 15,
                statusLabel: "서울 강남 집배점 도착 후 배송기사 인수"
            )
        ],
        truckConfig: .default
    ))
    .background(Color.black)
}

#Preview("잠금화면 — 폴백(이벤트 0)") {
    LockScreenLiveActivityView(state: .init(
        items: [
            TrackingItemState(
                trackingNumber: "123456789012",
                status: .outForDelivery,
                carrierName: "CJ대한통운",
                itemName: "무선 키보드",
                estimatedDelivery: "오늘 도착 예정"
            )
        ],
        truckConfig: .default
    ))
    .background(Color.black)
}

#Preview("잠금화면 — idle (트럭 + Waito)") {
    LockScreenLiveActivityView(state: .init(items: [], truckConfig: .default))
        .background(Color.black)
}
