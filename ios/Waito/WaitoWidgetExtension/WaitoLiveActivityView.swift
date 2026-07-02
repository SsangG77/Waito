import SwiftUI
import WidgetKit
import ActivityKit

/// 서버/앱이 보낸 날짜 문자열("YYYY-MM-DD HH:mm:ss")을 "YYYY.MM.DD" 로. (위젯은 문자열 파싱만)
private func waitoShortDate(_ raw: String?) -> String {
    guard let raw, raw.count >= 10 else { return raw ?? "" }
    return raw.prefix(10).replacingOccurrences(of: "-", with: ".")   // "2026-06-17 ..." → "2026.06.17"
}

struct WaitoLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DeliveryAttributes.self) { context in
            LockScreenLiveActivityView(state: context.state)
                .activityBackgroundTint(Color("bg"))
        } dynamicIsland: { context in
            let state = context.state
            return DynamicIsland {
                // 가운데: 물품명 + 타임라인 (세로)
                DynamicIslandExpandedRegion(.center) {
                    ExpandedMetroTimelineView(state: state)
                }
                // 아래: 출발 날짜(좌)  ⟷  물품 상태 라벨(우)
                DynamicIslandExpandedRegion(.bottom) {
                    if let primary = state.primary {
                        HStack {
                            Text(waitoShortDate(primary.departureDate))
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Color.wPixelMuted)
                                .lineLimit(1)
                            Spacer()
                            Text(primary.status.displayName)   // DI: 원본 메시지 대신 간단한 단계명(예: 간선상차)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Color.wPixelOrange)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .padding(.horizontal, 10)
                    }
                }
               
            } compactLeading: {
                let cfg = context.state.truckConfig
                CatalogTruckView(cab: cfg.cab, truckBody: cfg.body, wheels: cfg.wheelType, size: 24)
            } compactTrailing: {
                if let primary = context.state.primary {
                    DeliveryProgressRingView(progress: primary.status.progress, size: 20)
                        .padding(.horizontal, 3)
                }
            } minimal: {
                let cfg = context.state.truckConfig
                CatalogTruckView(cab: cfg.cab, truckBody: cfg.body, wheels: cfg.wheelType, size: 18)
            }
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
                estimatedDelivery: "오늘 도착 예정",
                eventCount: 5,
                statusLabel: "옥천HUB 간선상차",
                departureDate: "2026-06-17 09:00:00"   // 프리뷰 날짜 → "6/17"
            )
        ], truckConfig: .default)
    }

    /// 배송 없을 때(항상 노출) — 달리는 트럭 idle 상태
    static var idle: Self { .init(items: [], truckConfig: .default) }
}

private let _previewAttr = DeliveryAttributes(deviceId: "preview")


#Preview("잠금화면", as: .content, using: _previewAttr) {
    WaitoLiveActivity()
} contentStates: {
    DeliveryAttributes.ContentState.idle
    DeliveryAttributes.ContentState.make(status: .delivering)
    DeliveryAttributes.ContentState.make(status: .delivered)
}

#Preview("DI 펼침", as: .dynamicIsland(.expanded), using: _previewAttr) {
    WaitoLiveActivity()
} contentStates: {
    DeliveryAttributes.ContentState.idle
    DeliveryAttributes.ContentState.make(status: .outForDelivery)
}

#Preview("DI 접힘", as: .dynamicIsland(.compact), using: _previewAttr) {
    WaitoLiveActivity()
} contentStates: {
    DeliveryAttributes.ContentState.idle
    DeliveryAttributes.ContentState.make(status: .delivering)
}

#Preview("DI 최소", as: .dynamicIsland(.minimal), using: _previewAttr) {
    WaitoLiveActivity()
} contentStates: {
    DeliveryAttributes.ContentState.idle
}
