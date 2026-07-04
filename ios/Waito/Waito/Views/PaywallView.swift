import SwiftUI
import StoreKit

// Waito Plus 월간 구독. 가격(₩3,000/월)은 App Store Connect 에서 설정한다(코드는 상품 ID만 참조).
// ⚠️ App Store Connect 에 동일 ID 의 자동 갱신 구독을 등록해야 페이월에 표시됨. 로컬 테스트는 Waito.storekit 사용.
private let waitoPlusProductIDs: [String] = [
    "com.sangjin.Waito.plus.monthly"
]

/// 구독 결제 화면 필수 링크(App Store Guideline 3.1.2(c)) — 운영 서버가 제공하는 정적 페이지.
/// PlusPaywallView(커스텀)·PaywallView(StoreKit) 두 페이월이 공유한다.
enum WaitoLegal {
    static let privacyPolicy = URL(string: "http://158.247.223.154:3001/privacy")!
    static let termsOfUse    = URL(string: "http://158.247.223.154:3001/terms")!
}

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
        // 구독 필수 링크 — StoreKit 페이월 하단에 개인정보처리방침 / 이용약관(EULA) 노출
        .subscriptionStorePolicyDestination(url: WaitoLegal.privacyPolicy, for: .privacyPolicy)
        .subscriptionStorePolicyDestination(url: WaitoLegal.termsOfUse, for: .termsOfService)
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
