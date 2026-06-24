import Foundation
import StoreKit

/// StoreKit 2 접근 레이어 — 상품 로드 / 구매 / 복원 / 권한(entitlement) 확인.
/// View·상태관리에 의존하지 않는다(순수 외부 의존성 접근). 상태 보관은 SubscriptionManager 가 한다.
struct StoreKitService {
    enum StoreKitError: Error { case failedVerification }

    /// 구독 상품 ID 목록(현재 월간 1종). App Store Connect 에 동일 ID 로 등록돼야 한다.
    let productIDs: [String]

    /// App Store Connect 에서 상품 정보(가격 포함)를 받아온다.
    func loadProducts() async throws -> [Product] {
        try await Product.products(for: productIDs)
    }

    /// 구매 시도. 성공·검증 완료 시 true, 사용자 취소/보류 시 false.
    func purchase(_ product: Product) async throws -> Bool {
        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            await transaction.finish()   // 거래 완료 처리(미완료 시 반복 전달됨)
            return true
        case .userCancelled, .pending:
            return false
        @unknown default:
            return false
        }
    }

    /// 구매 복원 — App Store 와 동기화(기기 변경/재설치 대응). 실패 시 throw.
    func restore() async throws {
        try await AppStore.sync()
    }

    /// 현재 활성 구독 권한이 있는지(productIDs 중 하나라도, 미취소).
    func isEntitled() async -> Bool {
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if productIDs.contains(transaction.productID), transaction.revocationDate == nil {
                return true
            }
        }
        return false
    }

    /// 외부(App Store) 트랜잭션 변경을 지속 관찰 — 갱신/환불/타기기 구매 등. onUpdate 에서 권한 재확인.
    /// 반환 Task 를 보관했다 앱 종료 시 취소한다.
    func observeTransactionUpdates(onUpdate: @escaping @Sendable () async -> Void) -> Task<Void, Never> {
        Task.detached {
            for await _ in Transaction.updates {
                await onUpdate()
            }
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw StoreKitError.failedVerification   // 서명 검증 실패 → 신뢰하지 않음
        case .verified(let safe):
            return safe
        }
    }
}
