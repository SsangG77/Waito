//
//  ContentView.swift
//  Waito
//
//  Created by 김무경 on 3/17/26.
//

import SwiftUI

struct ContentView: View {
    @Environment(TrackingService.self) private var service

    var body: some View {
        NavigationStack {
            DeliveryListView()
        }
        .task {
            await service.loadCarriers()
            if service.deviceToken == nil {
                await service.registerDevice(token: UUID().uuidString)
            }
            await service.loadTrackings()
            // 디바이스 등록 후 push-to-start / update 토큰 관찰 시작 (무한 스트림 — 뷰 생명주기 동안 유지)
            async let pushToStart: Void = service.observePushToStartToken()
            async let activityUpdates: Void = service.observeActivityUpdates()
            _ = await (pushToStart, activityUpdates)
        }
        .overlay {
            DynamicIslandTruckOverlay()
        }
    }
}

// MARK: - 인앱 Dynamic Island 트럭 오버레이

struct DynamicIslandTruckOverlay: View {
    // pillWidth/pillHeight 하나만 조절하면 캡슐 + 트럭 경로 동시 변경
    private static let pillWidth: CGFloat = 158
    private static let pillHeight: CGFloat = 40

    private let islandYInset: CGFloat = -27   // Y 위치 조절용
    private let truckOffset: CGFloat = 6
    private let truckSize: CGFloat = 15
    private let animationPeriod: Double = 8.0

    var body: some View {
        GeometryReader { geo in
            let originX = (geo.size.width - Self.pillWidth) / 2
            let originY = (geo.safeAreaInsets.top - islandYInset) / 2
            let cfg = TruckConfigStore.shared.config

            Capsule()
                .fill(Color.black)
                .frame(width: Self.pillWidth, height: Self.pillHeight)
                .position(x: geo.size.width / 2, y: originY + Self.pillHeight / 2)

            TimelineView(.animation) { context in
                let pose = truckPose(at: context.date)
                CatalogTruckView(cab: cfg.cab, truckBody: cfg.body, wheels: cfg.wheelType, size: truckSize)
                    .scaleEffect(x: pose.isReversed ? -1 : 1, y: 1)
                    .position(
                        x: originX + pose.x,
                        y: originY - truckOffset
                    )
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    /// 상단 직선 위에서만 왕복. isReversed=true 면 왼쪽으로 진행 (트럭 좌우 반전)
    private func truckPose(at date: Date) -> (x: CGFloat, isReversed: Bool) {
        let elapsed = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: animationPeriod)
        let phase = elapsed / animationPeriod
        let isReversed = phase > 0.5
        let pingPong = phase <= 0.5 ? phase * 2 : (1.0 - phase) * 2
        let smooth = pingPong * pingPong * (3.0 - 2.0 * pingPong)

        let cornerRadius = Self.pillHeight / 2
        let startX = cornerRadius + 3
        let endX = Self.pillWidth - cornerRadius - 3
        let x = startX + (endX - startX) * CGFloat(smooth)
        return (x, isReversed)
    }
}

#Preview {
    ContentView()
        .environment(TrackingService(preview: [
            TrackingListItem(
                id: 1, carrierId: "cj", trackingNumber: "123456789012",
                itemName: "맥북 프로 14인치", currentStatus: .delivering,
                currentTValue: 0.8, carrierName: "CJ대한통운",
                estimatedDelivery: "오늘", createdAt: "2026-04-10T09:00:00Z", deliveredAt: nil
            ),
            
            TrackingListItem(
                id: 2, carrierId: "hanjin", trackingNumber: "987654321098",
                itemName: "에어팟 프로", currentStatus: .inTransitOut,
                currentTValue: 0.5, carrierName: "한진택배",
                estimatedDelivery: "내일", createdAt: "2026-04-09T15:30:00Z", deliveredAt: nil
            ),
        ]))
        .environment(SubscriptionManager())
}
