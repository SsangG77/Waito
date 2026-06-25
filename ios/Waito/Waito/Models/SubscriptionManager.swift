import Foundation
import Observation
import StoreKit

@MainActor
@Observable
final class SubscriptionManager {
    /// 구독 상태 미러 키 — TrackingService/위젯이 UserDefaults 로 방어적 재확인할 때 공유.
    /// (실제 구독 || 디버그 언락)의 결합 결과를 항상 여기에 동기화한다.
    static let storageKey = "waito_is_subscribed"
    /// 디버그 언락(설정 비밀번호) 영구 키 — 실제 구독과 분리.
    static let debugUnlockKey = "debug_unlocked"

    static let monthlyProductID = "com.sangjin.Waito.plus.monthly"

    private let store = StoreKitService(productIDs: [monthlyProductID])

    /// App Store 권한 기반 실제 구독 여부
    private(set) var isStoreSubscribed = false
    /// 디버그 언락 여부(실구독과 독립)
    private(set) var isDebugUnlocked = false
    /// 로드된 상품(가격 표시용)
    private(set) var products: [Product] = []

    private var updatesTask: Task<Void, Never>?

    /// 잠금 해제 판정 = 실제 구독 또는 디버그 언락. 기존 호출부는 이 값만 본다.
    var isSubscribed: Bool { isStoreSubscribed || isDebugUnlocked }

    /// 월간 상품 / 현지화 가격(₩3,000) — App Store Connect 에서 받아옴.
    var monthlyProduct: Product? { products.first(where: { $0.id == Self.monthlyProductID }) }
    var monthlyPriceText: String? { monthlyProduct?.displayPrice }
    /// 상품을 불러왔는지(구매 가능) — nil 이면 ASC 미등록/로딩중 → CTA 비활성.
    var isProductAvailable: Bool { monthlyProduct != nil }

    /// 구매 동선 UI 분기용 결과.
    enum PurchaseOutcome { case success, cancelled, failed, unavailable }

    init() {
        isDebugUnlocked = UserDefaults.standard.bool(forKey: Self.debugUnlockKey)
        syncStoredFlag()
    }

    // MARK: - StoreKit 수명주기

    /// 앱 시작 시 1회 호출 — 상품 로드 + 권한 확인 + 트랜잭션 관찰 시작.
    func start() async {
        await loadProducts()
        await refreshEntitlement()
        updatesTask?.cancel()
        updatesTask = store.observeTransactionUpdates { [weak self] in
            await self?.refreshEntitlement()
        }
    }

    func loadProducts() async {
        products = (try? await store.loadProducts()) ?? []
    }

    /// 현재 App Store 권한을 다시 확인해 isStoreSubscribed 갱신.
    func refreshEntitlement() async {
        isStoreSubscribed = await store.isEntitled()
        syncStoredFlag()
    }

    /// 월간 구독 구매. 실제 결제(Apple 시스템 시트)는 이 안에서 발생. 결과를 UI 분기용으로 반환.
    func purchaseMonthly() async -> PurchaseOutcome {
        guard let product = monthlyProduct else { return .unavailable }
        do {
            switch try await store.purchase(product) {
            case .success:
                await refreshEntitlement()
                return .success
            case .cancelled, .pending:
                return .cancelled   // 취소/보류 — 사용자에게 오류 알림을 띄우지 않는다
            }
        } catch {
            return .failed          // 검증/네트워크 실패 → 오류 안내 필요
        }
    }

    /// 구매 복원.
    func restore() async {
        try? await store.restore()
        await refreshEntitlement()
    }

    // MARK: - 디버그 언락 (실구독과 분리)

    func setDebugUnlocked(_ value: Bool) {
        isDebugUnlocked = value
        UserDefaults.standard.set(value, forKey: Self.debugUnlockKey)
        syncStoredFlag()
    }

    func toggleDebugUnlocked() {
        setDebugUnlocked(!isDebugUnlocked)
    }

    /// isSubscribed(결합 결과)를 공유 UserDefaults 키에 미러링 — TrackingService/위젯 재확인용.
    private func syncStoredFlag() {
        UserDefaults.standard.set(isSubscribed, forKey: Self.storageKey)
    }

    // MARK: - Premium 판별

    func isPremium(shape: TruckShape) -> Bool { shape != .standard }
    func isPremium(style: TruckStyle) -> Bool { style != .flat }
    func isPremium(color: TruckColor) -> Bool { ![TruckColor.white, .blue, .orange].contains(color) }

    func canUse(shape: TruckShape) -> Bool { isSubscribed || !isPremium(shape: shape) }
    func canUse(style: TruckStyle) -> Bool { isSubscribed || !isPremium(style: style) }
    func canUse(color: TruckColor) -> Bool { isSubscribed || !isPremium(color: color) }

    // MARK: - Live Activity 제한 / 항상 노출

    /// 무료 1개 / 유료 2개. (ActivityKit 4KB·잠금화면 높이 제약상 상한 둠)
    var liveActivityLimit: Int { isSubscribed ? 2 : 1 }
    var canUseAlwaysShow: Bool { isSubscribed }
}
