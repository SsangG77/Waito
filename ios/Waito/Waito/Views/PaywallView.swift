import SwiftUI
import StoreKit

// Waito Plus 월간 구독. 가격(₩3,000/월)은 App Store Connect 에서 설정한다(코드는 상품 ID만 참조).
// ⚠️ App Store Connect 에 동일 ID 의 자동 갱신 구독을 등록해야 페이월에 표시됨. 로컬 테스트는 Waito.storekit 사용.
private let waitoPlusProductIDs: [String] = [
    "com.sangjin.Waito.plus.monthly"
]

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SubscriptionManager.self) private var subscription

    var body: some View {
        SubscriptionStoreView(productIDs: waitoPlusProductIDs) {
            marketingContent
        }
        .storeButton(.visible, for: .restorePurchases)
        .storeButton(.visible, for: .cancellation)
        .subscriptionStoreButtonLabel(.action)
        // PlusPaywallView 와 동일한 어두운 배경 — 전체 높이에 bg 적용
        .containerBackground(Color.bg, for: .subscriptionStore)
        .preferredColorScheme(.dark)   // StoreKit 기본 컨트롤/텍스트가 어두운 배경에 맞게
        .onInAppPurchaseCompletion { _, result in
            if case .success(.success) = result {
                Task {
                    await subscription.refreshEntitlement()   // 구매 반영 → isSubscribed 갱신
                    dismiss()
                }
            }
        }
    }

    // StoreKit SubscriptionStoreView 의 마케팅 영역 — PlusPaywallView 와 동일한 히어로(트럭 그리드+혜택).
    // 실제 가격·구매 버튼은 이 아래에 StoreKit 이 자동으로 그린다.
    private var marketingContent: some View {
        PlusMarketingHero()
            .padding(.bottom, 8)
    }
}

#Preview {
    PaywallView()
        .environment(SubscriptionManager())
}
