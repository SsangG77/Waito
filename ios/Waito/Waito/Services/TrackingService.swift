import Foundation
import ActivityKit
import Observation

// MARK: - Tracking Service

@Observable
final class TrackingService {
    private(set) var trackings: [TrackingListItem] = []
    private(set) var carriers: [Carrier] = []
    private(set) var isLoading = false
    private(set) var error: String?

    func clearError() {
        error = nil
    }

    private let api = APIClient.shared
    private let deviceTokenKey = "waito_device_token"

    // MARK: - Device Token

    var deviceToken: String? {
        UserDefaults.standard.string(forKey: deviceTokenKey)
    }

    func registerDevice(token: String) async {
        do {
            _ = try await api.registerDevice(token: token)
            UserDefaults.standard.set(token, forKey: deviceTokenKey)
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Carriers

    func loadCarriers() async {
        do {
            carriers = try await api.getCarriers()
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Tracking CRUD

    func loadTrackings() async {
        guard let token = deviceToken else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            trackings = try await api.listTrackings(deviceToken: token)
            self.error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func addTracking(carrierId: String, trackingNumber: String, itemName: String?) async -> Bool {
        guard let token = deviceToken else { return false }
        do {
            let result = try await api.createTracking(
                deviceToken: token,
                carrierId: carrierId,
                trackingNumber: trackingNumber,
                itemName: itemName
            )
            await loadTrackings()
            await startLiveActivity(for: result)
            self.error = nil
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    func deleteTracking(id: Int) async {
        do {
            try await api.deleteTracking(id: id)
            trackings.removeAll { $0.id == id }
            self.error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func refreshTracking(id: Int) async {
        do {
            let updated = try await api.refreshTracking(id: id)
            if let index = trackings.firstIndex(where: { $0.id == id }) {
                trackings[index] = updated
            }
            self.error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func getTrackingDetail(id: Int) async -> TrackingDetail? {
        do {
            return try await api.getTracking(id: id)
        } catch {
            self.error = error.localizedDescription
            return nil
        }
    }

    // MARK: - Live Activity

    private func startLiveActivity(for tracking: TrackingCreateResponse) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let attributes = DeliveryAttributes(trackingNumber: tracking.trackingNumber)
        let state = DeliveryAttributes.ContentState(
            status: tracking.status,
            carrierName: tracking.carrierName,
            itemName: tracking.itemName,
            estimatedDelivery: nil,
            truckConfig: TruckConfigStore.shared.config
        )

        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: .init(state: state, staleDate: nil),
                pushType: .token
            )

            // Push token을 서버에 등록
            Task {
                for await tokenData in activity.pushTokenUpdates {
                    let token = tokenData.map { String(format: "%02x", $0) }.joined()
                    try? await api.updatePushToken(trackingId: tracking.id, pushToken: token)
                }
            }
        } catch {
            self.error = "Live Activity 시작 실패: \(error.localizedDescription)"
        }
    }
}
