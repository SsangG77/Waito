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

            HStack(spacing: 10) {
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

                Text("·")
                    .font(pixelFont(9))
                    .foregroundStyle(Color.pixelMuted)

                // 오퍼 코드(특가 코드) — Apple 공식 입력 시트를 띄운다(인앱 직접 입력은 불가).
                Button { showOfferCodeRedeem = true } label: {
                    Text("프로모션 코드")
                        .font(pixelFont(9))
                        .foregroundStyle(Color.pixelMuted)
                        .underline()
                }
                .buttonStyle(.plain)
            }
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
            truckGrid

            titleBlock
            benefits
                .padding(.top, 26)
                .padding(.horizontal, 22)
        }
    }

    // MARK: - 상단 트럭 그리드 (장식 — 가장자리로 흐르도록 클립)

    private var truckGrid: some View {
        GeometryReader { geo in
            let cols = 5
            let spacing: CGFloat = 15
            let bleed: CGFloat = 90   // 좌우로 흘러나가는 정도(가장자리 트럭이 반쯤 잘림)
            // 화면 폭에 맞춰 트럭 크기를 계산 → 기기 폭과 무관하게 항상 꽉 차고 가장자리만 살짝 잘림
            let size = (geo.size.width + bleed - spacing * CGFloat(cols - 1)) / CGFloat(cols)
            VStack(spacing: 10) {
                ForEach(Self.gridRows.indices, id: \.self) { idx in
                    // 행마다 좌/우 번갈아 천천히 흐르며 다른 조합이 계속 지나간다.
                    PaywallMarqueeRow(
                        combos: Self.gridRows[idx],
                        size: size,
                        spacing: spacing,
                        toLeft: idx.isMultiple(of: 2),
                        period: Double(Self.gridRows[idx].count) * 2.4
                    )
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
            .opacity(0.97)
        }
        .frame(height: 270)
        // 양옆으로 갈수록 투명해져 배경에 녹아드는 그라데이션 마스크
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.0),
                    .init(color: .black, location: 0.26),
                    .init(color: .black, location: 0.74),
                    .init(color: .clear, location: 1.0),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
    }

    // MARK: - 타이틀

    private var titleBlock: some View {
        VStack(spacing: 14) {
            Text("내 트럭을 무제한으로")
                .font(pixelFont(22))
                .foregroundStyle(gold)
                .multilineTextAlignment(.center)
                .lineSpacing(3)

            Text("Plus로 모든 조합과 알림을 잠금 해제하세요")
                .font(pixelFont(11))
                .foregroundStyle(Color.pixelMuted)
        }
        .padding(.top, 18)
    }

    // MARK: - 혜택 3종

    private var benefits: some View {
        VStack(spacing: 18) {
            benefitRow(icon: gridIcon, title: "24,000가지 트럭 조합", desc: "짐칸·헤드·바퀴를 섞어 나만의 트럭")
            benefitRow(icon: bellIcon, title: "한눈에 보는 배송 알림", desc: "여러 택배 상태를 알림창에서 동시에")
            benefitRow(icon: coinIcon, title: "하루 단 110원", desc: "커피 한 모금보다 저렴하게")
        }
    }

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

    // MARK: - 트럭 그리드 조합 (4행 × 8열) — 마퀴로 흐르므로 행마다 다양하게

    private static let gridRows: [[(TruckCab, TruckBody, TruckWheelType)]] = {
        let cabs = TruckCab.allCases
        let bodies = TruckBody.allCases
        let wheels = TruckWheelType.allCases
        let rows = 4
        let perRow = 8
        return (0..<rows).map { r in
            (0..<perRow).map { c -> (TruckCab, TruckBody, TruckWheelType) in
                let i = r * perRow + c
                return (
                    cabs[(i * 7 + r) % cabs.count],
                    bodies[(i * 5 + r * 3) % bodies.count],
                    wheels[(i * 3 + r) % wheels.count]
                )
            }
        }
    }()
}

// MARK: - 페이월 트럭 마퀴 행 (좌/우로 끊김 없이 순환)

/// 한 행의 콤보를 2벌 이어붙여 offset 을 한 벌 너비만큼 선형 반복 → 끊김 없는 순환.
private struct PaywallMarqueeRow: View {
    let combos: [(TruckCab, TruckBody, TruckWheelType)]
    let size: CGFloat
    let spacing: CGFloat
    let toLeft: Bool
    let period: Double

    @State private var animate = false

    var body: some View {
        let count = combos.count
        let rowWidth = (size + spacing) * CGFloat(count)   // 한 벌 너비 = 순환 주기 거리
        HStack(spacing: spacing) {
            ForEach(0..<(count * 2), id: \.self) { i in
                let c = combos[i % count]
                CatalogTruckView(cab: c.0, truckBody: c.1, wheels: c.2, size: size)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .offset(x: offsetX(rowWidth: rowWidth))
        .animation(.linear(duration: period).repeatForever(autoreverses: false), value: animate)
        .onAppear { animate = true }
    }

    private func offsetX(rowWidth: CGFloat) -> CGFloat {
        if toLeft {
            return animate ? -rowWidth : 0          // 0 → -rowWidth (왼쪽으로 흐름)
        } else {
            return animate ? 0 : -rowWidth          // -rowWidth → 0 (오른쪽으로 흐름)
        }
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
