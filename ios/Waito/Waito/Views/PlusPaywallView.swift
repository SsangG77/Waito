import SwiftUI
import StoreKit   // .offerCodeRedemption 모디파이어

/// Waito Plus 업셀 모달 — 잠긴 트럭/옵션을 탭했을 때 뜨는 풀스크린 페이월.
/// 상단 트럭 그리드 + 혜택 3종 + 가격 + 구독 CTA.
/// 구매는 내부에서 SubscriptionManager.purchaseMonthly() 로 처리(실제 StoreKit 결제). 성공 시 onPurchased 후처리.
struct PlusPaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SubscriptionManager.self) private var subscription

    /// 구매 성공(또는 디버그 구독) 직후 실행 — 예: 미리보던 트럭 조합 커밋. (구매 동작 자체는 내부 처리)
    var onPurchased: () -> Void = {}

    /// 포인트 부족으로 띄운 경우 보유/부족 포인트를 함께 표시. 그 외 진입점은 nil → 미표시.
    var pointStatus: PointStatus? = nil
    struct PointStatus { let need: Int; let balance: Int }

    @State private var isPurchasing = false
    @State private var showPurchaseError = false
    @State private var showOfferCodeRedeem = false   // Apple 오퍼 코드(특가 코드) 입력 시트

    // 디자인 골드 팔레트
    private let gold = Color(hex: "#E8C24A")        // 가격·코인
    private let buttonGold = Color(hex: "#F2CF63")  // CTA 버튼
    private let buttonText = Color(hex: "#16243B")  // CTA 글자(짙은 네이비)

    var body: some View {
        ZStack(alignment: .top) {
            Color.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                PlusMarketingHero()   // 공유 마케팅 히어로(트럭 그리드 + 타이틀 + 혜택)

                Spacer(minLength: 16)

                // 구독 중이어도 화면은 그대로 노출 — CTA 버튼만 "구독중" + 비활성으로 표시된다.
                if let ps = pointStatus, !subscription.isSubscribed {
                    pointStatusBlock(ps)
                        .padding(.bottom, 12)
                }
                priceBlock
                ctaButton
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                offerCodeButton
                    .padding(.top, 12)
                footer
            }

            closeButton
        }
        .alert("구매를 완료하지 못했어요", isPresented: $showPurchaseError) {
            Button("확인", role: .cancel) {}
        } message: {
            Text("잠시 후 다시 시도하거나, 이미 구독 중이라면 ‘구매 복원’을 눌러주세요.")
        }
        // 오퍼 코드(특가 코드) 입력 — Apple 시트. 성공 시 Transaction.updates 가 권한을 자동 반영하지만,
        // 즉시 화면 갱신을 위해 닫힌 직후 한 번 더 확인하고 구독되면 닫는다.
        .offerCodeRedemption(isPresented: $showOfferCodeRedeem) { result in
            Task {
                if case .success = result {
                    await subscription.refreshEntitlement()
                    if subscription.isSubscribed { dismiss() }
                }
            }
        }
    }

    // MARK: - 가격 / CTA / 푸터

    /// 포인트 부족 안내 — 내 포인트 + 부족분 (포인트 경로로 띄웠을 때만)
    private func pointStatusBlock(_ ps: PointStatus) -> some View {
        let short = max(ps.need - ps.balance, 0)
        return HStack(spacing: 8) {
            Image(systemName: "star.fill")
                .font(.system(size: 11))
                .foregroundStyle(gold)
            Text("내 포인트 \(ps.balance)P")
                .font(pixelFont(11))
                .foregroundStyle(.white.opacity(0.9))
            Text("·")
                .font(pixelFont(11))
                .foregroundStyle(Color.pixelMuted)
            Text("\(short)P 부족")
                .font(pixelFont(11))
                .foregroundStyle(gold)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(Color.pixelSurface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.pixelBorder, lineWidth: 1))
    }

    private var priceBlock: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("₩110")
                .font(pixelFont(30))
                .foregroundStyle(gold)
            Text("/ 1 day")
                .font(pixelFont(14))
                .foregroundStyle(.white.opacity(0.85))
        }
    }

    private var ctaButton: some View {
        // 구독 중이면 "구독중" + 비활성. 아니면 원래대로 — 상품 로딩 전(ASC 미등록/네트워크)에는
        // 구매 불가 → 비활성 + 안내, 준비되면 "구독 시작하기".
        let subscribed = subscription.isSubscribed
        let ready = subscription.isProductAvailable
        let enabled = !subscribed && ready && !isPurchasing
        return Button {
            startPurchase()
        } label: {
            Group {
                if isPurchasing {
                    ProgressView().tint(buttonText)
                } else {
                    Text(subscribed ? "구독중" : (ready ? "구독 시작하기" : "상품 불러오는 중…"))
                        .font(pixelFont(14))
                        .foregroundStyle(buttonText)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(buttonGold)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .opacity(enabled ? 1 : 0.5)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    /// 구독 시작하기 — Apple 시스템 결제 시트가 이 안에서 뜬다. 결과에 따라 분기.
    private func startPurchase() {
        guard !isPurchasing else { return }
        isPurchasing = true
        Task {
            let outcome = await subscription.purchaseMonthly()
            isPurchasing = false
            switch outcome {
            case .success:
                onPurchased()
                dismiss()
            case .failed, .unavailable:
                showPurchaseError = true       // 진짜 실패만 알림
            case .cancelled:
                break                          // 사용자 취소 — 조용히 페이월 유지
            }
        }
    }

    /// 오퍼 코드(특가 코드) — CTA 바로 아래 독립 줄. Apple 공식 입력 시트를 띄운다(인앱 직접 입력은 불가).
    private var offerCodeButton: some View {
        Button { showOfferCodeRedeem = true } label: {
            Text("프로모션 코드")
                .font(pixelFont(12))   // 눈에 띄도록 다른 푸터 텍스트(9)보다 3pt 크게
                .foregroundStyle(Color.pixelMuted)
                .underline()
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        VStack(spacing: 8) {
            // 구독 필수 정보(제목·기간·가격) 명시 — App Store Guideline 3.1.2(c).
            // 큰 ₩110 은 하루 단위 마케팅, 여기서 실제 상품명·기간·월 가격을 투명하게 표기.
            Text("Waito Plus · 1개월 자동 갱신 · 월 \(subscription.monthlyPriceText ?? "₩3,300")")
                .font(pixelFont(9))
                .foregroundStyle(Color.pixelMuted)
                .multilineTextAlignment(.center)

            // 필수 링크 — 개인정보처리방침 / 이용약관(EULA). 탭 시 Safari 로 열림.
            HStack(spacing: 10) {
                Link(destination: WaitoLegal.privacyPolicy) {
                    Text("개인정보처리방침")
                        .font(pixelFont(9))
                        .foregroundStyle(Color.pixelMuted)
                        .underline()
                }
                Text("·")
                    .font(pixelFont(9))
                    .foregroundStyle(Color.pixelMuted)
                Link(destination: WaitoLegal.termsOfUse) {
                    Text("이용약관")
                        .font(pixelFont(9))
                        .foregroundStyle(Color.pixelMuted)
                        .underline()
                }
            }

            Button {
                Task {
                    await subscription.restore()
                    if subscription.isSubscribed { dismiss() }
                }
            } label: {
                Text("구매 복원")
                    .font(pixelFont(9))
                    .foregroundStyle(Color.pixelMuted)
                    .underline()
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    // MARK: - 닫기 버튼

    private var closeButton: some View {
        HStack {
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(width: 32, height: 32)
                    .background(Color.black.opacity(0.35))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }
}

// MARK: - 공유 마케팅 히어로 (트럭 그리드 + 타이틀 + 혜택)
// PlusPaywallView 와 PaywallView(StoreKit SubscriptionStoreView 의 marketingContent) 가 공용으로 쓴다.
// → StoreKit 페이월도 동일한 디자인을 갖고, 실제 가격·구매 버튼은 StoreKit 이 아래에 그린다.

struct PlusMarketingHero: View {
    private let gold = Color(hex: "#E8C24A")
    private let buttonText = Color(hex: "#16243B")

    var body: some View {
        VStack(spacing: 0) {
            // 상단 히어로 = 잠금화면에 택배 2개가 동시에 뜨는 모습(실제 위젯 뷰).
            // 피드백상 유저가 체감하는 구독 가치가 트럭 스킨보다 "동시 2개 추적"이라 유틸을 앞세운다.
            PaywallLockScreenPreview()

            titleBlock
            benefits
                .padding(.top, 26)
                .padding(.horizontal, 22)
        }
    }

    // MARK: - 타이틀

    private var titleBlock: some View {
        VStack(spacing: 14) {
            // 포지셔닝 문구 통일 — "실시간 추적"이 아니라 "앱 안 열어도 보인다"가 핵심 가치.
            Text("택배 2개까지 잠금화면에 동시에")
                .font(pixelFont(22))
                .foregroundStyle(gold)
                .multilineTextAlignment(.center)
                .lineSpacing(3)

            Text("앱 안 열어도 보입니다")
                .font(pixelFont(11))
                .foregroundStyle(Color.pixelMuted)
        }
        .padding(.top, 18)
    }

    // MARK: - 혜택 3종

    private var benefits: some View {
        // 순서 = 체감 가치 순. 피드백에서 "동시 2개 추적"이 가장 유용하다고 나와 유틸을 위로,
        // 트럭 스킨은 보조로 내렸다.
        VStack(spacing: 14) {
            benefitRow(icon: bellIcon, title: "택배 2개를 동시에", desc: "잠금화면·다이나믹 아일랜드에 함께 표시")
            benefitRow(icon: mapIcon, title: "지도로 보는 배송 경로", desc: "지나온 지점과 지금 위치를 한눈에")
            benefitRow(icon: gridIcon, title: "\(Self.comboCountText)가지 트럭 조합", desc: "짐칸·헤드·바퀴를 섞어 나만의 트럭")
            benefitRow(icon: coinIcon, title: "하루 단 110원", desc: "커피 한 모금보다 저렴하게")
        }
    }

    /// 카탈로그에서 직접 계산 — 부품이 늘어도 문구가 따라간다(하드코딩 시 실제 개수와 어긋남).
    private static let comboCountText: String = {
        let total = TruckCab.allCases.count * TruckBody.allCases.count * TruckWheelType.allCases.count
        return NumberFormatter.localizedString(from: NSNumber(value: total), number: .decimal)
    }()

    private func benefitRow<Icon: View>(icon: Icon, title: String, desc: String) -> some View {
        HStack(spacing: 16) {
            icon
                .frame(width: 56, height: 56)
                .background(Color.pixelSurface)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.pixelBorder, lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(pixelFont(12))
                    .foregroundStyle(.white)
                Text(desc)
                    .font(pixelFont(9))
                    .foregroundStyle(Color.pixelMuted)
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: - 혜택 아이콘 (픽셀 스타일)

    /// 지도 아이콘 — 지나온 지점(회색 네모) 둘을 점선으로 잇고 현재 지점을 빨강으로.
    private var mapIcon: some View {
        ZStack {
            Path { p in
                p.move(to: CGPoint(x: 6, y: 34))
                p.addLine(to: CGPoint(x: 20, y: 20))
                p.addLine(to: CGPoint(x: 38, y: 8))
            }
            .stroke(Color.pixelMuted, style: StrokeStyle(lineWidth: 2, dash: [3, 3]))

            Rectangle().fill(Color.pixelMuted).frame(width: 8, height: 8)
                .position(x: 6, y: 34)
            Rectangle().fill(Color.pixelMuted).frame(width: 8, height: 8)
                .position(x: 20, y: 20)
            Rectangle().fill(Color(hex: "#E5484D")).frame(width: 12, height: 12)
                .position(x: 38, y: 8)
        }
        .frame(width: 44, height: 42)
    }

    private var gridIcon: some View {
        let colors: [Color] = [
            Color(hex: "#E5484D"), Color(hex: "#E8A838"), Color(hex: "#E8C24A"),
            Color(hex: "#22C55E"), Color(hex: "#3B82F6"), Color(hex: "#9457E8"),
            Color(hex: "#FF6B95"), Color(hex: "#22C5C5"), Color(hex: "#7CD66B"),
        ]
        return VStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { r in
                HStack(spacing: 3) {
                    ForEach(0..<3, id: \.self) { c in
                        Rectangle()
                            .fill(colors[r * 3 + c])
                            .frame(width: 8, height: 8)
                    }
                }
            }
        }
    }

    private var bellIcon: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 5) {
                ForEach(0..<3, id: \.self) { i in
                    Rectangle()
                        .fill(.white.opacity(i == 0 ? 0.9 : 0.45))
                        .frame(width: i == 0 ? 20 : 26, height: 3)
                }
            }
            Circle()
                .fill(Color(hex: "#E5484D"))
                .frame(width: 7, height: 7)
                .offset(x: 5, y: -5)
        }
        .frame(width: 26, height: 22)
    }

    private var coinIcon: some View {
        ZStack {
            Circle().fill(gold)
            Circle()
                .stroke(buttonText.opacity(0.55), lineWidth: 2)
                .padding(5)
        }
        .frame(width: 26, height: 26)
    }

}

#Preview("기본") {
    PlusPaywallView()
        .environment(SubscriptionManager())
}

#Preview("포인트 부족 동반") {
    PlusPaywallView(pointStatus: .init(need: 3, balance: 1))
        .environment(SubscriptionManager())
}
