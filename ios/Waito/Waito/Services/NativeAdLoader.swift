import Foundation
import Observation
import UIKit
import GoogleMobileAds

/// 네이티브 광고 한 개를 불러와 들고 있는다. 목록의 광고 슬롯마다 하나씩 만든다
/// (같은 광고 객체를 여러 자리에 붙이면 노출 집계가 중복된다).
@MainActor
@Observable
final class NativeAdLoader: NSObject {
    /// 광고 단위 ID. DEBUG 는 구글 공개 테스트 단위, RELEASE 는 실계정 단위.
    /// (개발 중 실제 광고를 부르면 무효 트래픽으로 계정이 정지될 수 있다 — 구글 정책)
    #if DEBUG
    static let unitID = "ca-app-pub-3940256099942544/3986624511"
    #else
    static let unitID = "ca-app-pub-3545555975398754/8244575612"   // Waito 목록 네이티브
    #endif

    private(set) var ad: NativeAd?

    private var loader: AdLoader?

    /// 동의 절차(AdConsentService)가 끝나 광고 요청이 허용된 뒤에만 실제로 부른다.
    func load() {
        guard ad == nil, loader == nil, AdConsentService.shared.canRequestAds else { return }

        let options = NativeAdViewAdOptions()
        options.preferredAdChoicesPosition = .topRightCorner

        let loader = AdLoader(
            adUnitID: Self.unitID,
            rootViewController: AdConsentService.rootViewController,
            adTypes: [.native],
            options: [options],
        )
        loader.delegate = self
        self.loader = loader
        loader.load(Request())
    }
}

extension NativeAdLoader: NativeAdLoaderDelegate {
    nonisolated func adLoader(_ adLoader: AdLoader, didReceive nativeAd: NativeAd) {
        Task { @MainActor in self.ad = nativeAd }
    }

    nonisolated func adLoader(_ adLoader: AdLoader, didFailToReceiveAdWithError error: Error) {
        // 광고가 없거나 네트워크가 막힌 상황. 자리를 비우고 조용히 넘어간다.
        #if DEBUG
        NSLog("[Ad] 로드 실패: %@", error.localizedDescription)
        #endif
        Task { @MainActor in self.loader = nil }
    }
}
