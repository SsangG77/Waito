import SwiftUI
import WidgetKit
import ActivityKit

struct WaitoLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DeliveryAttributes.self) { context in
            LockScreenLiveActivityView(state: context.state)
                .activityBackgroundTint(.black)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.bottom, priority: 1) {
                    ExpandedBorderTruckView(state: context.state)
                        .padding(.top, -28)
                }
            } compactLeading: {
                BouncingTruckView(config: context.state.truckConfig, size: 24)
            } compactTrailing: {
                if let primary = context.state.primary {
                    DeliveryProgressRingView(progress: primary.status.progress, size: 20)
                        .padding(.horizontal, 3)
                }
            } minimal: {
                let cfg = context.state.truckConfig
                CatalogTruckView(cab: cfg.cab, truckBody: cfg.body, wheels: cfg.wheelType, size: 18)
            }
            .contentMargins(.top, -28, for: .expanded)
            .contentMargins([.leading, .trailing, .bottom], 0, for: .expanded)
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
                estimatedDelivery: "오늘 도착 예정"
            )
        ], truckConfig: .default)
    }
}

private let _previewAttr = DeliveryAttributes(deviceId: "preview")

#Preview("Expanded — 배송중", as: .dynamicIsland(.expanded), using: _previewAttr) {
    WaitoLiveActivity()
} contentStates: {
    DeliveryAttributes.ContentState.make(status: .delivering)
}

#Preview("Expanded — 배송완료", as: .dynamicIsland(.expanded), using: _previewAttr) {
    WaitoLiveActivity()
} contentStates: {
    DeliveryAttributes.ContentState.make(status: .delivered)
}

#Preview("Expanded — 접수", as: .dynamicIsland(.expanded), using: _previewAttr) {
    WaitoLiveActivity()
} contentStates: {
    DeliveryAttributes.ContentState.make(status: .registered)
}

#Preview("Lock Screen", as: .content, using: _previewAttr) {
    WaitoLiveActivity()
} contentStates: {
    DeliveryAttributes.ContentState.make(status: .delivering)
    DeliveryAttributes.ContentState.make(status: .delivered)
}
