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
        liveTrackingNumbers = UserDefaults.standard.stringArray(forKey: liveTrackingsKey) ?? []
        trackings = [
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
        ]
    }

    /// 프리뷰 전용
    init(preview trackings: [TrackingListItem]) {
        self.trackings = trackings
        self.liveTrackingNumbers = []
    }

    // MARK: - 더미 데이터 (서버 없을 때 fallback)

    func loadDummyDataIfNeeded() {
        guard trackings.isEmpty else { return }
        trackings = [
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
        ]
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

    /// 트럭 설정 변경 시 실행 중인 모든 Live Activity에 즉시 반영
    func pushTruckConfig() async {
        var newConfig = TruckConfigStore.shared.config
        for activity in Activity<DeliveryAttributes>.activities {
            var newState = activity.content.state
            newConfig.runMode = newState.truckConfig.runMode  // on/off 모드 유지
            newState.truckConfig = newConfig
            await activity.update(.init(state: newState, staleDate: nil))
        }
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

    // MARK: - Debug

    #if DEBUG
    func startDemoLiveActivity() async {
        let demoItem = TrackingItemState(
            trackingNumber: "DEMO-0000",
            status: .delivering,
            carrierName: "Waito Demo",
            itemName: "데모 택배",
            estimatedDelivery: "오늘"
        )
        var config = TruckConfigStore.shared.config
        config.runMode = .on
        let state = DeliveryAttributes.ContentState(items: [demoItem], truckConfig: config)
        let attributes = DeliveryAttributes(deviceId: "demo")
        do {
            _ = try Activity.request(
                attributes: attributes,
                content: .init(state: state, staleDate: nil),
                pushType: nil
            )
        } catch {
            self.error = "Live Activity 오류: \(error)"
        }
    }

    func stopDemoLiveActivity() async {
        await endLiveActivity()
    }
    #endif
}
