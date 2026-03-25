import ActivityKit
import Foundation

struct DeliveryAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var status: DeliveryStatus
        var carrierName: String
        var itemName: String
        var estimatedDelivery: String?
        var truckConfig: TruckConfig = .default
    }

    var trackingNumber: String
}
