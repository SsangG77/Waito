import SwiftUI
import WidgetKit
import ActivityKit

struct WaitoLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DeliveryAttributes.self) { context in
            LockScreenLiveActivityView(state: context.state)
                .activityBackgroundTint(Color("bg"))
        } dynamicIsland: { context in
            let state = context.state
            return DynamicIsland {
                // 가운데: 좌 트럭 20% + 우측(물품명 → 가로 타임라인 → 상태·날짜)
                // 상태·날짜가 center 안으로 들어가 bottom 영역은 사용하지 않는다.
                DynamicIslandExpandedRegion(.center) {
                    ExpandedMetroTimelineView(state: state)
                }
            } compactLeading: {
                if let primary = context.state.primary {
                    DeliveryProgressRingView(progress: primary.status.progress, size: 20)
                        .padding(.horizontal, 3)
                }
            } compactTrailing: {
                let cfg = context.state.truckConfig
                CatalogTruckView(cab: cfg.cab, truckBody: cfg.body, wheels: cfg.wheelType, size: 24)
            } minimal: {
                let cfg = context.state.truckConfig
                // 다른 앱과 공존해 작은 원으로 밀렸을 때: 중앙 트럭 + 주변 얇은 진행 링.
                // (배송 없음 idle 이면 진행률이 없으니 트럭만)
                if let primary = context.state.primary {
                    MinimalTruckRingView(progress: primary.status.progress, config: cfg)
                } else {
                    CatalogTruckView(cab: cfg.cab, truckBody: cfg.body, wheels: cfg.wheelType, size: 18)
                }
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
