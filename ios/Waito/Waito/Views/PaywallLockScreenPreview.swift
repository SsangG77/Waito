import SwiftUI

/// 페이월 상단 히어로 — "잠금화면에 택배 2개가 동시에 뜬다"를 실제 위젯 뷰로 보여준다.
///
/// 잠금화면 카드는 위젯의 `LockScreenLiveActivityView` 를 그대로 렌더한다(양 타깃 공유 파일).
/// 페이월은 인앱이라 위젯의 애니메이션 제약(content state 변경 시에만 갱신)을 받지 않으므로,
/// 1개 → 2개로 늘어나는 과정을 SwiftUI 애니메이션으로 한 번 재생한다(반복 없음).
struct PaywallLockScreenPreview: View {
    /// 두 번째 택배가 등장했는지 — onAppear 에서 한 번만 true 로 전환된다.
    @State private var showsSecondItem = false

    /// 유저가 고른 트럭을 그대로 보여준다 — "내 트럭이 잠금화면에 뜬다"가 되도록.
    private var truckConfig: TruckConfig { TruckConfigStore.shared.config }

    private var items: [TrackingItemState] {
        showsSecondItem ? [Self.firstItem, Self.secondItem] : [Self.firstItem]
    }

    var body: some View {
        lockScreenCard
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 22)
            .padding(.top, 8)
            .accessibilityIdentifier("paywall_lockscreen_preview")
            .onAppear(perform: playOnce)
    }

    // MARK: - 실제 잠금화면 Live Activity 카드

    private var lockScreenCard: some View {
        LockScreenLiveActivityView(
            state: .init(items: items, truckConfig: truckConfig)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.pixelBorder, lineWidth: 1)
        )
        .accessibilityIdentifier("paywall_lockscreen_card")
    }

    // MARK: - 1회 재생

    /// 화면 진입 후 잠깐 1개만 보여준 뒤, 두 번째 택배가 밀려 들어온다. 반복하지 않는다.
    private func playOnce() {
        guard !showsSecondItem else { return }
        withAnimation(.spring(response: 0.55, dampingFraction: 0.78).delay(0.9)) {
            showsSecondItem = true
        }
    }

    // MARK: - 데모 데이터

    private static let firstItem = TrackingItemState(
        trackingNumber: "paywall-demo-1",
        status: .outForDelivery,
        carrierName: "CJ대한통운",
        itemName: "무선 이어폰",
        estimatedDelivery: "오늘 도착 예정",
        statusLabel: "배송출발"
    )

    private static let secondItem = TrackingItemState(
        trackingNumber: "paywall-demo-2",
        status: .inTransitIn,
        carrierName: "한진택배",
        itemName: "러닝화",
        estimatedDelivery: "내일 도착 예정",
        statusLabel: "간선상차"
    )

}

#Preview("페이월 잠금화면 프리뷰") {
    ZStack {
        Color.bg.ignoresSafeArea()
        PaywallLockScreenPreview()
    }
}
