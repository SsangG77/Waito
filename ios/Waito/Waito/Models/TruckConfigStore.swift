import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class TruckConfigStore {
    static let shared = TruckConfigStore()

    var config: TruckConfig {
        didSet { save() }
    }

    private let key = "waito_truck_config"

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode(TruckConfig.self, from: data) {
            self.config = saved
        } else {
            self.config = .default
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}



#Preview {
    let service = TrackingService(preview: [
        TrackingListItem(
            id: 1,
            carrierId: "cj",
            trackingNumber: "123456789012",
            itemName: "맥북 프로 14인치",
            currentStatus: .delivering,
            currentTValue: 0.8,
            carrierName: "CJ대한통운",
            estimatedDelivery: "오늘",
            createdAt: "2026-04-10T09:00:00Z",
            deliveredAt: nil
        ),
        TrackingListItem(
            id: 2,
            carrierId: "hanjin",
            trackingNumber: "987654321098",
            itemName: "에어팟 프로",
            currentStatus: .inTransitOut,
            currentTValue: 0.5,
            carrierName: "한진택배",
            estimatedDelivery: "내일",
            createdAt: "2026-04-09T15:30:00Z",
            deliveredAt: nil
        ),
        TrackingListItem(
            id: 3,
            carrierId: "lotte",
            trackingNumber: "555444333222",
            itemName: "Nike 에어맥스",
            currentStatus: .delivered,
            currentTValue: 0.95,
            carrierName: "롯데택배",
            estimatedDelivery: nil,
            createdAt: "2026-04-07T11:00:00Z",
            deliveredAt: "2026-04-11T14:22:00Z"
        ),
        TrackingListItem(
            id: 4,
            carrierId: "post",
            trackingNumber: "111222333444",
            itemName: "무선 키보드",
            currentStatus: .registered,
            currentTValue: 0.05,
            carrierName: "우체국택배",
            estimatedDelivery: "3일 후",
            createdAt: "2026-04-12T08:00:00Z",
            deliveredAt: nil
        ),
    ])
    NavigationStack {
        DeliveryListView()
    }
    .environment(service)
    .environment(SubscriptionManager())
}
