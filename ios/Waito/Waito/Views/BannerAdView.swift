import SwiftUI
import UIKit
import GoogleMobileAds

/// 화면 맨 아래에 붙는 배너 광고. 목록이 비어 있을 때(달리는 트럭 화면) 무료 사용자에게만 부모가 붙인다.
/// 동의 절차가 끝나기 전이나 출시판 광고 단위가 비어 있으면 아무것도 그리지 않는다.
struct BannerAdSlot: View {
    /// 광고 단위 ID. DEBUG 는 구글 공개 테스트 배너, RELEASE 는 실계정 배너 단위.
    /// (개발 중 실제 광고를 부르면 무효 트래픽으로 계정이 정지될 수 있다 — 구글 정책)
    #if DEBUG
    static let unitID: String? = "ca-app-pub-3940256099942544/2934735716"
    #else
    static let unitID: String? = "ca-app-pub-3545555975398754/2973981728"   // Waito 빈 화면 배너
    #endif

    var body: some View {
        if let unitID = Self.unitID, AdConsentService.shared.canRequestAds {
            GeometryReader { geo in
                BannerAdView(unitID: unitID, width: geo.size.width)
            }
            .frame(height: Self.height)
            .frame(maxWidth: .infinity)
            .background(Color.bg)
            .accessibilityIdentifier("empty_banner_ad")
        }
    }

    /// 화면 폭에 맞춘 배너 높이(구글 권장 "적응형 고정 배너" 크기)
    private static var height: CGFloat {
        let width = AdConsentService.rootViewController?.view.bounds.width ?? 390
        return currentOrientationAnchoredAdaptiveBanner(width: width).size.height
    }
}

/// 구글 배너 화면(UIKit)을 SwiftUI 에 끼운다.
private struct BannerAdView: UIViewRepresentable {
    let unitID: String
    let width: CGFloat

    func makeUIView(context: Context) -> BannerView {
        let banner = BannerView(adSize: currentOrientationAnchoredAdaptiveBanner(width: width))
        banner.adUnitID = unitID
        banner.rootViewController = AdConsentService.rootViewController
        banner.load(Request())
        return banner
    }

    func updateUIView(_ uiView: BannerView, context: Context) {}
}
