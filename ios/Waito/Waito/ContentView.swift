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
            service.loadDummyDataIfNeeded()
        }
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
            TrackingListItem(
                id: 3, carrierId: "lotte", trackingNumber: "555444333222",
                itemName: "Nike 에어맥스", currentStatus: .delivered,
                currentTValue: 0.95, carrierName: "롯데택배",
                estimatedDelivery: nil, createdAt: "2026-04-07T11:00:00Z",
                deliveredAt: "2026-04-11T14:22:00Z"
            ),
            TrackingListItem(
                id: 4, carrierId: "post", trackingNumber: "111222333444",
                itemName: "무선 키보드", currentStatus: .registered,
                currentTValue: 0.05, carrierName: "우체국택배",
                estimatedDelivery: "3일 후", createdAt: "2026-04-12T08:00:00Z", deliveredAt: nil
            ),
        ]))
        .environment(SubscriptionManager())
}
