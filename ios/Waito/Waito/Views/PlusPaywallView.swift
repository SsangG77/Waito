import SwiftUI

/// Waito Plus 업셀 모달 — 잠긴 트럭/옵션을 탭했을 때 뜨는 풀스크린 페이월.
/// 상단 트럭 그리드 + 혜택 3종 + 가격 + 구독 CTA.
/// 실제 구매 연결은 `onSubscribe` 로 위임한다(현재는 호출부에서 처리).
struct PlusPaywallView: View {
    @Environment(\.dismiss) private var dismiss

    /// "구독 시작하기" 탭 시 실행 (실제 StoreKit 구매 연결 지점)
    var onSubscribe: () -> Void = {}

    // 디자인 골드 팔레트
    private let gold = Color(hex: "#E8C24A")        // 타이틀·가격·코인
    private let buttonGold = Color(hex: "#F2CF63")  // CTA 버튼
    private let buttonText = Color(hex: "#16243B")  // CTA 글자(짙은 네이비)

    var body: some View {
        ZStack(alignment: .top) {
            Color.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                truckGrid

                titleBlock
                benefits
                    .padding(.top, 26)
                    .padding(.horizontal, 22)

                Spacer(minLength: 16)

                priceBlock
                ctaButton
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                footer
            }

            closeButton
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
                    let row = Self.gridRows[idx]
                    HStack(spacing: spacing) {
                        ForEach(row.indices, id: \.self) { c in
                            CatalogTruckView(cab: row[c].0, truckBody: row[c].1, wheels: row[c].2, size: size)
                        }
                    }
                    // 행마다 반 칸씩 엇갈리게(브릭 패턴) — 양옆은 마스크로 흐려짐
                    .offset(x: idx.isMultiple(of: 2) ? -(size + spacing) / 4 : (size + spacing) / 4)
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
            benefitRow(icon: coinIcon, title: "하루 단 200원", desc: "커피 한 모금보다 저렴하게")
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

    // MARK: - 가격 / CTA / 푸터

    private var priceBlock: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("₩200")
                .font(pixelFont(30))
                .foregroundStyle(gold)
            Text("/ 하루")
                .font(pixelFont(14))
                .foregroundStyle(.white.opacity(0.85))
        }
    }

    private var ctaButton: some View {
        Button {
            onSubscribe()
            dismiss()
        } label: {
            Text("구독 시작하기")
                .font(pixelFont(14))
                .foregroundStyle(buttonText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(buttonGold)
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        Text("언제든지 해지할 수 있어요 · 자동 갱신")
            .font(pixelFont(9))
            .foregroundStyle(Color.pixelMuted)
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

    // MARK: - 트럭 그리드 조합 (4행 × 5열)

    private static let gridRows: [[(TruckCab, TruckBody, TruckWheelType)]] = {
        let cabs = TruckCab.allCases
        let bodies = TruckBody.allCases
        let wheels = TruckWheelType.allCases
        let combos: [(TruckCab, TruckBody, TruckWheelType)] = (0..<20).map { i in
            (cabs[i % cabs.count], bodies[(i * 3) % bodies.count], wheels[(i * 5) % wheels.count])
        }
        return stride(from: 0, to: combos.count, by: 5).map { Array(combos[$0..<min($0 + 5, combos.count)]) }
    }()
}

#Preview {
    PlusPaywallView()
}
