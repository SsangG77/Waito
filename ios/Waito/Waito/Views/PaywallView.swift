import SwiftUI
import StoreKit

// TODO: App Store Connect에 실제 상품 등록 후 ID 교체
//       현재는 플레이스홀더 — 등록 전까지 시트가 빈 상태로 표시됨
private let waitoPlusProductIDs: [String] = [
    "com.sangjin.Waito.plus.monthly",
    "com.sangjin.Waito.plus.yearly"
]

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SubscriptionStoreView(productIDs: waitoPlusProductIDs) {
            marketingContent
        }
        .storeButton(.visible, for: .restorePurchases)
        .storeButton(.visible, for: .cancellation)
        .subscriptionStoreButtonLabel(.action)
        .onInAppPurchaseCompletion { _, result in
            if case .success(.success) = result {
                // TODO: Transaction.currentEntitlements 구독 후 SubscriptionManager 동기화
                dismiss()
            }
        }
    }

    private var marketingContent: some View {
        VStack(spacing: 16) {
            Text("🚚")
                .font(.system(size: 56))
                .padding(.top, 24)

            Text("WAITO PLUS")
                .font(pixelFont(20))
                .foregroundStyle(Color.pixelText)

            Text("더 많은 택배, 더 귀여운 트럭")
                .font(pixelFont(11))
                .foregroundStyle(Color.pixelMuted)

            VStack(alignment: .leading, spacing: 10) {
                benefitRow(icon: "📦", text: "Live Activity 2개 동시 추적")
                benefitRow(icon: "🎨", text: "모든 트럭 스킨 잠금 해제")
                benefitRow(icon: "✨", text: "시즌 한정 트럭")
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
        }
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity)
    }

    private func benefitRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Text(icon)
                .font(.system(size: 18))
            Text(text)
                .font(pixelFont(11))
                .foregroundStyle(Color.pixelText)
            Spacer(minLength: 0)
        }
    }
}

#Preview {
    PaywallView()
}
