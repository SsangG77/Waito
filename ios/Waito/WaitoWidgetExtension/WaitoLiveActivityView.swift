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
                DynamicIslandExpandedRegion(.bottom) { EmptyView() }
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


#Preview("Lock Screen", as: .content, using: _previewAttr) {
    WaitoLiveActivity()
} contentStates: {
    DeliveryAttributes.ContentState.make(status: .delivering)
    DeliveryAttributes.ContentState.make(status: .delivered)
}
