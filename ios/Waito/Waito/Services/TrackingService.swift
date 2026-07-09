import Foundation
import ActivityKit
import Observation
import Security

// MARK: - Add Tracking Result

enum AddTrackingResult {
    /// 추가 성공 — 새로 만들어진 tracking id (목록 바운스 강조용)
    case success(id: Int)
    /// 운송장 조회 불가 — 확인 다이얼로그 후 force 재시도 대상
    case notFound(message: String)
    case failure
}

// MARK: - Tracking Service

@MainActor
@Observable
final class TrackingService {
    private(set) var trackings: [TrackingListItem] = []
    private(set) var carriers: [Carrier] = []
    private(set) var isLoading = false
    private(set) var error: String?

    /// Live Activity에 등록된 택배 운송장 번호 목록
    private(set) var liveTrackingNumbers: [String] = []

    /// 배송완료 누적 = 획득 포인트 (디바이스별, 서버 보관)
    private(set) var deliveredCount = 0
    /// 포인트로 해제한 부품 rawValue 집합
    private(set) var unlockedParts: Set<String> = []
    /// 사용 가능한 잔여 포인트 = 획득 - 해제수 * 비용
    var pointBalance: Int { max(0, deliveredCount - unlockedParts.count * pointUnlockCost) }

    func isUnlocked(_ partRawValue: String) -> Bool { unlockedParts.contains(partRawValue) }

    func clearError() {
        error = nil
    }

    private let api = APIClient.shared
    /// 디바이스 식별 UUID 의 Keychain 키 (AppDelegate 도 동일 키로 읽어 APNs 토큰을 등록)
    static let deviceTokenKeychainKey = "waito_device_token"
    private let deviceTokenKey = TrackingService.deviceTokenKeychainKey
    private let liveTrackingsKey = "waito_live_tracking_numbers"
    /// "항상 노출"(배송 없어도 Dynamic Island 트럭 유지) 토글 저장 키 — SettingsView @AppStorage 와 공유
    /// ⚠️ 값 변경 시 기존 사용자 설정이 초기화되므로 마이그레이션 필요
    static let alwaysShowKey = "waito_always_show_di"
    /// 테스트(더미) 데이터 토글 저장 키 — SettingsView/DeliveryListView @AppStorage 와 공유
    static let showDummyDataKey = "debug_show_dummy_data"

    /// 현재 테스트 데이터 토글 ON 여부 (토글이 꺼지면 더미는 더 이상 유효 항목이 아님)
    private var showDummyData: Bool {
        UserDefaults.standard.bool(forKey: Self.showDummyDataKey)
    }

    // MARK: - Init

    init() {
        liveTrackingNumbers = UserDefaults.standard.stringArray(forKey: liveTrackingsKey) ?? []
    }

    /// 프리뷰 전용
    init(preview trackings: [TrackingListItem]) {
        self.trackings = trackings
        self.liveTrackingNumbers = []
    }

    // MARK: - Device Token

    /// 디바이스 토큰은 Keychain 에 저장한다 — UserDefaults 와 달리 앱 삭제 후 재설치에도
    /// 남으므로, 디바이스 단위 진행도(예: 배송 완료 누적 카운트)가 리셋되지 않는다.
    /// 기존 사용자(UserDefaults 에 토큰 보유)는 최초 접근 시 1회 Keychain 으로 이전한다.
    var deviceToken: String? {
        if let token = Keychain.read(deviceTokenKey) { return token }
        if let legacy = UserDefaults.standard.string(forKey: deviceTokenKey) {
            Keychain.save(legacy, for: deviceTokenKey)
            UserDefaults.standard.removeObject(forKey: deviceTokenKey)
            return legacy
        }
        return nil
    }

    func registerDevice(token: String) async {
        do {
            _ = try await api.registerDevice(token: token)
            Keychain.save(token, for: deviceTokenKey)
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
            // Live Activity 집합 정리: 현재 목록에 존재하고(=삭제된 택배 유령 제거) 미완료인 번호만 남긴다.
            // (삭제건이 남으면 count 가 부풀려져 무료 1개 한도가 잘못 소진된다)
            // ⚠️ 더미(디버그/테스트) 번호는 토글 ON 일 때만 유효로 포함 — 토글이 꺼지면 정리 대상이 되어
            //    LA/DI 에 남은 더미가 제거된다. (토글 ON 직후엔 포함되어 즉시 OFF 되는 문제도 방지)
            let validCandidates = showDummyData ? (trackings + Self.dummyTrackings) : trackings
            let activeNumbers = Set(
                validCandidates
                    .filter { !$0.currentStatus.isCompleted }
                    .map(\.trackingNumber)
            )
            let before = liveTrackingNumbers.count
            liveTrackingNumbers.removeAll { !activeNumbers.contains($0) }
            if liveTrackingNumbers.count != before {
                saveLiveTrackingNumbers()
            }
            // 토글된 배송 아이템이 있으면 배송 LA 우선, 없으면 ambient/종료 — 항상 단일 기준으로 조정.
            // (완료건 유무와 무관하게 호출해야, "배송중 아이템만 토글 ON" 상태에서도 배송 LA 가 표시됨)
            await reconcileLiveActivity()
            self.error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func addTracking(
        carrierId: String,
        trackingNumber: String,
        itemName: String?,
        memo: String? = nil,
        limit: Int = 1,
        force: Bool = false
    ) async -> AddTrackingResult {
        guard let token = deviceToken else { return .failure }
        do {
            let result = try await api.createTracking(
                deviceToken: token,
                carrierId: carrierId,
                trackingNumber: trackingNumber,
                itemName: itemName,
                memo: memo,
                force: force
            )
            await loadTrackings()

            // 여유가 있으면 자동으로 Live Activity에 추가
            if liveTrackingNumbers.count < limit {
                await addToLiveActivity(trackingNumber: result.trackingNumber)
            }

            self.error = nil
            return .success(id: result.id)
        } catch APIError.trackingNotFound(let message) {
            // 조회 불가 — 호출부에서 확인 다이얼로그를 띄운다 (에러로 표시하지 않음)
            return .notFound(message: message)
        } catch {
            self.error = error.localizedDescription
            return .failure
        }
    }

    /// 품명/메모 수정. 성공 시 로컬 목록과 Live Activity 를 갱신한다.
    func updateTracking(id: Int, itemName: String?, memo: String?) async -> Bool {
        do {
            let updated = try await api.updateTracking(id: id, itemName: itemName, memo: memo)
            if let index = trackings.firstIndex(where: { $0.id == id }) {
                trackings[index] = updated
            }
            await updateLiveActivity()
            self.error = nil
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    // MARK: - 진행도(포인트) / 부품 해제

    /// 서버에서 배송완료 포인트 + 해제 부품을 불러온다.
    func loadDeviceProgress() async {
        guard let token = deviceToken else { return }
        if let progress = try? await api.getDeviceProgress(deviceToken: token) {
            deliveredCount = progress.deliveredCount
            unlockedParts = Set(progress.unlockedParts)
        }
    }

    /// 포인트로 부품 1개 해제. 성공 시 로컬 상태 갱신.
    func unlockPart(_ partRawValue: String) async -> Bool {
        guard let token = deviceToken else { return false }
        do {
            let progress = try await api.unlockPart(deviceToken: token, part: partRawValue)
            deliveredCount = progress.deliveredCount
            unlockedParts = Set(progress.unlockedParts)
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

    /// pull-to-refresh: 목록의 각 택배를 서버에서 실제 재조회(택배사 폴링)한 뒤,
    /// events 포함 목록을 다시 로드해 상태를 최신값으로 반영한다.
    /// (loadTrackings 만으로는 DB 캐시 상태만 읽혀 폴링 주기 전까지 최신이 아님)
    func refreshAll() async {
        guard deviceToken != nil else { return }
        // 완료건은 종료 상태라 폴링해도 안 바뀌므로 활성 택배만 병렬 재조회
        let ids = trackings.filter { !$0.currentStatus.isCompleted }.map(\.id)
        await withTaskGroup(of: Void.self) { group in
            for id in ids {
                group.addTask { [api] in
                    _ = try? await api.refreshTracking(id: id)
                }
            }
        }
        // 폴링으로 갱신된 상태 + 이벤트를 events 포함 목록으로 다시 로드
        await loadTrackings()
    }

    func getTrackingDetail(id: Int) async -> TrackingDetail? {
        do {
            return try await api.getTracking(id: id)
        } catch {
            self.error = error.localizedDescription
            return nil
        }
    }

    // MARK: - 항상 노출 (배송 없어도 Dynamic Island 트럭 유지)

    /// 설정의 "항상 노출" 토글 상태
    var alwaysShowDynamicIsland: Bool {
        UserDefaults.standard.bool(forKey: Self.alwaysShowKey)
    }

    /// 구독 여부 — SubscriptionManager 와 동일 키를 공유해 방어적으로 재확인한다.
    /// (구독이 만료됐는데 토글이 켜진 채로 남아 ambient 가 동작하는 것을 막는다)
    private var isSubscribed: Bool {
        UserDefaults.standard.bool(forKey: SubscriptionManager.storageKey)
    }

    /// 배송 없어도 트럭을 띄울 수 있는 상태 (토글 ON + 구독)
    private var ambientEnabled: Bool {
        alwaysShowDynamicIsland && isSubscribed
    }

    /// 설정에서 "항상 노출" 토글 변경 시 호출 — 저장 후 ambient Activity 를 즉시 반영.
    func setAlwaysShow(_ on: Bool) async {
        UserDefaults.standard.set(on, forKey: Self.alwaysShowKey)
        await reconcileAmbientActivity()
    }

    /// Live Activity 단일 조정점(SSoT).
    /// 우선순위: **토글된 배송 아이템 > ambient(항상 노출) > 종료**.
    /// "항상 노출"이 켜져 있어도 배송 아이템 토글이 켜져 있으면 배송 상태 LA/DI 를 우선 표시한다.
    func reconcileLiveActivity() async {
        if !liveTrackingNumbers.isEmpty {
            await updateLiveActivity()    // 배송 상태 LA/DI (ambient 보다 우선, 내부에서 서버 동기화)
        } else {
            // LA 목록이 비었음을 서버에 반영 → 다음 상태 변경 push 가 남은 items 없이 LA 를 종료
            await syncLiveActivityToServer()
            if ambientEnabled {
                await startAmbientActivity()  // 배송 없음 + 항상 노출 → 트럭만
            } else {
                await endLiveActivity()
            }
        }
    }

    /// 앱 진입 시 호출. 토글된 배송 아이템이 있으면 배송 LA, 없으면 ambient 로 조정한다.
    /// (단일 조정점에 위임 — updateLiveActivity/startAmbientActivity 모두 기존 Activity 를
    ///  덮어쓰지 않고 갱신하므로 복원된 Activity 를 안전하게 다룬다)
    func startAmbientIfEnabled() async {
        await reconcileLiveActivity()
    }

    /// 설정의 "항상 노출"/구독 변경 등에서 호출. (단일 조정점에 위임)
    func reconcileAmbientActivity() async {
        await reconcileLiveActivity()
    }

    /// items 없이 트럭만 담은 ambient 콘텐츠. (DI compact/minimal 은 items 없이도 트럭을 그린다)
    private func ambientContentState() -> DeliveryAttributes.ContentState {
        DeliveryAttributes.ContentState(items: [], truckConfig: TruckConfigStore.shared.config)
    }

    /// ambient Live Activity 시작/유지. 서버 푸시가 필요 없으므로 로컬 전용(pushType: nil).
    /// 이미 Activity 가 있으면 ambient(빈 items) 상태로 업데이트한다.
    /// (바운스는 자동 재생하지 않음 — 잠금화면 "> BOUNCE" 버튼 탭 시 BounceTruckIntent 가 처리)
    private func startAmbientActivity() async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        if let activity = Activity<DeliveryAttributes>.activities.first {
            await activity.update(.init(state: ambientContentState(), staleDate: nil))
            return
        }

        let attributes = DeliveryAttributes(deviceId: deviceToken ?? "unknown")
        do {
            _ = try Activity.request(
                attributes: attributes,
                content: .init(state: ambientContentState(), staleDate: nil),
                pushType: nil
            )
        } catch {
            self.error = "Live Activity 시작 실패: \(error.localizedDescription)"
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

    /// 테스트 데이터 토글 OFF 시 호출 — LA/DI 에 남아있는 더미 택배 번호를 즉시 제거하고 재조정.
    /// (loadTrackings 의 정리에도 의존하지만, 토글 끄는 즉시 반영되도록 별도 진입점을 둔다)
    func purgeDummyFromLiveActivity() async {
        let dummyNumbers = Set(Self.dummyTrackings.map(\.trackingNumber))
        let before = liveTrackingNumbers.count
        liveTrackingNumbers.removeAll { dummyNumbers.contains($0) }
        if liveTrackingNumbers.count != before {
            saveLiveTrackingNumbers()
        }
        await reconcileLiveActivity()
    }

    /// Live Activity에서 택배 제거
    func removeFromLiveActivity(trackingNumber: String) async {
        liveTrackingNumbers.removeAll { $0 == trackingNumber }
        saveLiveTrackingNumbers()

        // 남은 배송 아이템이 있으면 배송 LA 유지, 없으면 항상 노출 ON 시 ambient(트럭만)로 전환·아니면 종료
        await reconcileLiveActivity()
    }

    // MARK: - Private

    private func saveLiveTrackingNumbers() {
        UserDefaults.standard.set(liveTrackingNumbers, forKey: liveTrackingsKey)
    }

    private func buildContentState() -> DeliveryAttributes.ContentState {
        let items: [TrackingItemState] = liveTrackingNumbers.compactMap { number in
            // 실제 목록에서 먼저 찾고, 없으면 더미(디버그/테스트 데이터)에서 폴백 — 더미도 LA 에 표시되게.
            guard let tracking = trackings.first(where: { $0.trackingNumber == number })
                ?? Self.dummyTrackings.first(where: { $0.trackingNumber == number }) else { return nil }
            return TrackingItemState(
                trackingNumber: tracking.trackingNumber,
                status: tracking.currentStatus,
                carrierName: tracking.carrierName,
                itemName: tracking.itemName,
                estimatedDelivery: tracking.estimatedDelivery,
                // 가변 타임라인 compact 필드 — 로컬 Activity 와 서버 push 가 동일 shape 가 되도록.
                eventCount: tracking.events?.count,
                statusLabel: tracking.events?.last?.description,
                departureDate: tracking.createdAt        // 목록의 등록(출발) 날짜
            )
        }

        return DeliveryAttributes.ContentState(
            items: items,
            truckConfig: TruckConfigStore.shared.config
        )
    }

    /// 현재 LA 에 담긴 택배들의 서버 id 목록(순서 보존, 더미/미등록 제외)
    private func liveTrackingIds() -> [Int] {
        liveTrackingNumbers.compactMap { number in
            trackings.first(where: { $0.trackingNumber == number })?.id
        }
    }

    /// LA 목록(+선택적으로 갱신 토큰)을 디바이스 단위로 서버에 동기화.
    /// 서버는 이 목록으로 상태 변경 시 전체 items 를 재구성해 하나의 LA 토큰으로 보낸다(다중 택배 정합).
    private func syncLiveActivityToServer(pushToken: String? = nil) async {
        guard let deviceToken else { return }
        try? await api.syncLiveActivity(
            deviceToken: deviceToken,
            trackingIds: liveTrackingIds(),
            pushToken: pushToken,
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
        // LA 에 담긴 택배 목록을 서버에 반영(상태 변경 push 가 전체 items 를 재구성하는 근거)
        await syncLiveActivityToServer()
        let state = buildContentState()

        // 중복 LA 정리 — 여러 개 떠 있으면 하나만 남기고 종료(단일 인스턴스 보장).
        // 이미 쌓여버린 옛 LA(예: 접수 상태로 멈춘 것)를 앱 진입/갱신 시 청소한다.
        if let keep = Activity<DeliveryAttributes>.activities.first {
            await endActivities(except: keep)
        }

        // 이미 활성 Activity가 있으면 업데이트
        if let activity = Activity<DeliveryAttributes>.activities.first {
            // 기존이 ambient(빈 items, 푸시 토큰 미등록)면, 서버 푸시를 받을 수 있도록
            // 푸시 토큰을 갖춘 배송 Activity로 교체한다.
            if activity.content.state.items.isEmpty {
                await activity.end(nil, dismissalPolicy: .immediate)
                await startLiveActivity(state: state)
            } else {
                await activity.update(.init(state: state, staleDate: nil))
            }
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

            // LA 갱신 토큰을 디바이스 단위로 서버에 등록 (어느 택배가 바뀌든 이 하나의 토큰으로 전체 items 갱신)
            Task {
                for await tokenData in activity.pushTokenUpdates {
                    let token = tokenData.map { String(format: "%02x", $0) }.joined()
                    await syncLiveActivityToServer(pushToken: token)
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

    // MARK: - Push-to-Start (8시간 한도 후 재시작 대비)

    /// push-to-start 토큰을 관찰해 서버에 등록한다. 앱 시작 시 호출(무한 스트림이므로 백그라운드 Task에서).
    /// iOS 17.2+ 에서만 동작. Live Activity 를 앱에서 시작하지 않아도 토큰을 받을 수 있다.
    func observePushToStartToken() async {
        guard #available(iOS 17.2, *) else { return }
        for await tokenData in Activity<DeliveryAttributes>.pushToStartTokenUpdates {
            // 디바이스 미등록 상태면 이번 토큰은 보류. 스트림은 유지되므로 등록 후 다음 토큰(회전)에서 전송된다.
            guard let device = deviceToken else { continue }
            let token = tokenData.map { String(format: "%02x", $0) }.joined()
            try? await api.registerPushToStartToken(
                deviceToken: device,
                pushToStartToken: token,
                truckConfig: TruckConfigStore.shared.config
            )
        }
    }

    /// push-to-start 로 새로 시작된 Activity 의 update 토큰을 서버에 등록한다. 앱 시작 시 호출(무한 스트림).
    func observeActivityUpdates() async {
        for await activity in Activity<DeliveryAttributes>.activityUpdates {
            // 단일 인스턴스 보장: 새 Activity(대개 push-to-start 로 되살아난 것)가 뜨면
            // 이전 중복 Activity 들을 모두 종료 → "같은 택배가 여러 LA 로 쌓이는" 현상 방지.
            await endActivities(except: activity)
            observeUpdateToken(for: activity)
        }
    }

    /// keep 을 제외한 모든 활성 Activity 를 즉시 종료(중복 LA 정리).
    private func endActivities(except keep: Activity<DeliveryAttributes>) async {
        for activity in Activity<DeliveryAttributes>.activities where activity.id != keep.id {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    private func observeUpdateToken(for activity: Activity<DeliveryAttributes>) {
        Task {
            for await tokenData in activity.pushTokenUpdates {
                let token = tokenData.map { String(format: "%02x", $0) }.joined()
                await registerUpdateToken(token, for: activity)
            }
        }
    }

    private func registerUpdateToken(_ token: String, for activity: Activity<DeliveryAttributes>) async {
        // push-to-start 로 되살아난 Activity 의 update 토큰을 '디바이스 레벨'에 등록한다.
        // 서버 pushTrackingUpdate 는 devices.live_activity_push_token 으로만 in-place update 하므로,
        // 이 토큰을 tracking 레벨(updatePushToken)에만 등록하면 서버가 못 읽어 매 상태변경마다
        // update 실패 → push-to-start → "같은 택배가 새 LA 로 재생성"되는 버그가 난다.
        // la_tracking_ids 는 서버가 이미 갖고 있으므로 덮어쓰지 않는다(trackingIds: nil).
        guard let deviceToken else { return }
        try? await api.syncLiveActivity(
            deviceToken: deviceToken,
            trackingIds: nil,
            pushToken: token,
            truckConfig: TruckConfigStore.shared.config
        )
    }

    /// 트럭 설정이 바뀌면 push-to-start 페이로드에 쓰일 서버 측 트럭 설정도 갱신한다.
    func refreshPushToStartConfig() async {
        guard #available(iOS 17.2, *) else { return }
        guard let device = deviceToken,
              let tokenData = Activity<DeliveryAttributes>.pushToStartToken else { return }
        let token = tokenData.map { String(format: "%02x", $0) }.joined()
        try? await api.registerPushToStartToken(
            deviceToken: device,
            pushToStartToken: token,
            truckConfig: TruckConfigStore.shared.config
        )
    }

    // MARK: - Debug

    /// (디버그 토글/설정 비밀번호 언락) 목록에 표시할 더미 택배 데이터 — 릴리즈에서도 비번으로 켤 수 있어 컴파일 포함
    static let dummyTrackings: [TrackingListItem] = [
        TrackingListItem(
            id: 1, carrierId: "cj", trackingNumber: "123456789012",
            itemName: "맥북 프로 14인치", currentStatus: .delivering,
            currentTValue: 0.8, carrierName: "CJ대한통운",
            estimatedDelivery: "오늘", createdAt: "2026-04-10T09:00:00Z", deliveredAt: nil,
            lastEventTime: "2026-04-11T10:00:00Z"
        ),
        TrackingListItem(
            id: 2, carrierId: "hanjin", trackingNumber: "987654321098",
            itemName: "에어팟 프로", currentStatus: .inTransitOut,
            currentTValue: 0.5, carrierName: "한진택배",
            estimatedDelivery: "내일", createdAt: "2026-04-09T15:30:00Z", deliveredAt: nil,
            lastEventTime: "2026-04-10T08:00:00Z"
        ),
        TrackingListItem(
            id: 3, carrierId: "lotte", trackingNumber: "555444333222",
            itemName: "Nike 에어맥스", currentStatus: .delivered,
            currentTValue: 0.95, carrierName: "롯데택배",
            estimatedDelivery: nil, createdAt: "2026-04-07T11:00:00Z",
            deliveredAt: "2026-04-11T14:22:00Z", lastEventTime: "2026-04-11T14:22:00Z"
        ),
        TrackingListItem(
            id: 4, carrierId: "post", trackingNumber: "111222333444",
            itemName: "무선 키보드", currentStatus: .registered,
            currentTValue: 0.05, carrierName: "우체국택배",
            estimatedDelivery: "3일 후", createdAt: "2026-04-12T08:00:00Z", deliveredAt: nil
        ),
    ]

}

// MARK: - Keychain (디바이스 토큰 등 영속 식별자 저장)
// UserDefaults 와 달리 앱 삭제 후 재설치에도 값이 남는다(같은 기기 한정).
// 기기 간 동기화는 2차 개발의 로그인 기능에서 처리한다.
// (별도 파일 Services/Keychain.swift 로 분리 가능 — Xcode 타깃 등록 필요)
enum Keychain {
    @discardableResult
    static func save(_ value: String, for key: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        if SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess {
            return SecItemUpdate(query as CFDictionary, attributes as CFDictionary) == errSecSuccess
        }
        var addQuery = query
        addQuery.merge(attributes) { _, new in new }
        return SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess
    }

    static func read(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else { return nil }
        return value
    }

    @discardableResult
    static func delete(_ key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
