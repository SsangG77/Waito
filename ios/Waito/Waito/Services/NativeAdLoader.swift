import Foundation
import Observation
import UIKit
import GoogleMobileAds

/// 네이티브 광고 한 개를 불러와 들고 있는다. 목록의 광고 슬롯마다 하나씩 만든다
/// (같은 광고 객체를 여러 자리에 붙이면 노출 집계가 중복된다).
@MainActor
@Observable
final class NativeAdLoader: NSObject {
    /// 구글이 공개한 테스트 광고 단위. 실제 계정 발급 ID 로 바꾸기 전까지 이 값만 쓴다.
    /// (개발 중 실제 광고를 부르면 계정이 정지될 수 있다 — 구글 정책)
    static let testUnitID = "ca-app-pub-3940256099942544/3986624511"

    private(set) var ad: NativeAd?

    private var loader: AdLoader?

    /// 앱 시작 시 1회. 광고를 부르기 전에 반드시 먼저 호출돼야 한다.
    static func startSDK() {
        MobileAds.shared.start()
    }

    func load() {
        guard ad == nil, loader == nil else { return }

        let options = NativeAdViewAdOptions()
        options.preferredAdChoicesPosition = .topRightCorner

        let loader = AdLoader(
            adUnitID: Self.testUnitID,
            rootViewController: Self.rootViewController,
            adTypes: [.native],
            options: [options],
        )
        loader.delegate = self
        self.loader = loader
        loader.load(Request())
    }

    /// 광고 SDK 가 화면 전환(클릭 후 이동)에 쓰는 기준 화면.
    private static var rootViewController: UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController
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
