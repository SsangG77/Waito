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

    /// Live Activity에 등록된 택배 운송장 번호 목록
    private(set) var liveTrackingNumbers: [String] = []

    func clearError() {
        error = nil
    }

    private let api = APIClient.shared
    private let deviceTokenKey = "waito_device_token"
    private let liveTrackingsKey = "waito_live_tracking_numbers"

    // MARK: - Init

    init() {
        // 저장된 Live Activity 택배 목록 복원
        liveTrackingNumbers = UserDefaults.standard.stringArray(forKey: liveTrackingsKey) ?? []
    }

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
            // 완료된 택배는 Live Activity에서 제거
            let completed = trackings.filter { $0.currentStatus.isCompleted }.map(\.trackingNumber)
            if !completed.isEmpty {
                liveTrackingNumbers.removeAll { completed.contains($0) }
                saveLiveTrackingNumbers()
                await updateLiveActivity()
            }
            self.error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func addTracking(carrierId: String, trackingNumber: String, itemName: String?, limit: Int = 1) async -> Bool {
        guard let token = deviceToken else { return false }
        do {
            let result = try await api.createTracking(
                deviceToken: token,
                carrierId: carrierId,
                trackingNumber: trackingNumber,
                itemName: itemName
            )
            await loadTrackings()

            // 여유가 있으면 자동으로 Live Activity에 추가
            if liveTrackingNumbers.count < limit {
                await addToLiveActivity(trackingNumber: result.trackingNumber)
            }

            self.error = nil
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    func deleteTracking(id: Int) async {
        if let tracking = trackings.first(where: { $0.id == id }) {
            await removeFromLiveActivity(trackingNumber: tracking.trackingNumber)
        }
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
            await updateLiveActivity()
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

    // MARK: - Live Activity 관리 (싱글 인스턴스, 다중 택배)

    /// 특정 택배가 Live Activity에 등록되어 있는지
    func isInLiveActivity(trackingNumber: String) -> Bool {
        liveTrackingNumbers.contains(trackingNumber)
    }

    /// Live Activity에 택배 추가
    func addToLiveActivity(trackingNumber: String) async {
        guard !liveTrackingNumbers.contains(trackingNumber) else { return }
        liveTrackingNumbers.append(trackingNumber)
        saveLiveTrackingNumbers()
        await updateLiveActivity()
    }

    /// Live Activity에서 택배 제거
    func removeFromLiveActivity(trackingNumber: String) async {
        liveTrackingNumbers.removeAll { $0 == trackingNumber }
        saveLiveTrackingNumbers()

        if liveTrackingNumbers.isEmpty {
            await endLiveActivity()
        } else {
            await updateLiveActivity()
        }
    }

    // MARK: - Private

    private func saveLiveTrackingNumbers() {
        UserDefaults.standard.set(liveTrackingNumbers, forKey: liveTrackingsKey)
    }

    private func buildContentState() -> DeliveryAttributes.ContentState {
        let items: [TrackingItemState] = liveTrackingNumbers.compactMap { number in
            guard let tracking = trackings.first(where: { $0.trackingNumber == number }) else { return nil }
            return TrackingItemState(
                trackingNumber: tracking.trackingNumber,
                status: tracking.currentStatus,
                carrierName: tracking.carrierName,
                itemName: tracking.itemName,
                estimatedDelivery: tracking.estimatedDelivery
            )
        }

        return DeliveryAttributes.ContentState(
            items: items,
            truckConfig: TruckConfigStore.shared.config
        )
    }

    private func updateLiveActivity() async {
        guard !liveTrackingNumbers.isEmpty else { return }
        let state = buildContentState()

        // 이미 활성 Activity가 있으면 업데이트
        if let activity = Activity<DeliveryAttributes>.activities.first {
            await activity.update(.init(state: state, staleDate: nil))
            return
        }

        // 없으면 새로 생성
        await startLiveActivity(state: state)
    }

    private func startLiveActivity(state: DeliveryAttributes.ContentState) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let attributes = DeliveryAttributes(deviceId: deviceToken ?? "unknown")

        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: .init(state: state, staleDate: nil),
                pushType: .token
            )

            // Push token을 서버에 등록 (첫 번째 택배 ID 사용)
            if let firstNumber = liveTrackingNumbers.first,
               let tracking = trackings.first(where: { $0.trackingNumber == firstNumber }) {
                Task {
                    for await tokenData in activity.pushTokenUpdates {
                        let token = tokenData.map { String(format: "%02x", $0) }.joined()
                        try? await api.updatePushToken(trackingId: tracking.id, pushToken: token)
                    }
                }
            }
        } catch {
            self.error = "Live Activity 시작 실패: \(error.localizedDescription)"
        }
    }

    private func endLiveActivity() async {
        for activity in Activity<DeliveryAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
