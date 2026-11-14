import Foundation
import Observation
import UIKit
import GoogleMobileAds

/// 끝까지 보면 보상을 주는 광고(포인트 받기, 지도 1번 보기) 한 편을 미리 불러와 들고 있다.
/// 화면마다 하나씩 만든다. 한 번 보여주면 다음 편을 바로 다시 불러온다.
@MainActor
@Observable
final class RewardedAdLoader: NSObject {
    /// 광고 단위 ID. DEBUG 는 구글 공개 테스트 단위, RELEASE 는 실계정 단위.
    /// (개발 중 실제 광고를 부르면 무효 트래픽으로 계정이 정지될 수 있다 — 구글 정책)
    #if DEBUG
    static let unitID: String? = "ca-app-pub-3940256099942544/1712485313"
    #else
    static let unitID: String? = "ca-app-pub-3545555975398754/9284239206"   // Waito 보상형 (포인트, 지도)
    #endif

    /// 광고 기능 자체를 쓸 수 있는지 (출시판 단위가 비어 있으면 false → 버튼 숨김)
    static var isAvailable: Bool { unitID != nil }

    private(set) var ad: RewardedAd?
    private var loading = false
    /// 지금 보여주는 광고에서 보상 조건을 채웠는지 / 광고가 닫힌 뒤 부를 일
    private var earned = false
    private var pendingReward: (@MainActor () -> Void)?

    var isReady: Bool { ad != nil }

    /// 동의 절차가 끝나 광고 요청이 허용된 뒤에만 실제로 부른다.
    func load() {
        guard let unitID = Self.unitID, ad == nil, !loading, AdConsentService.shared.canRequestAds else { return }
        loading = true
        RewardedAd.load(with: unitID, request: Request()) { [weak self] ad, error in
            Task { @MainActor in
                guard let self else { return }
                self.loading = false
                self.ad = ad
                #if DEBUG
                if let error { NSLog("[Ad] 보상 광고 로드 실패: %@", error.localizedDescription) }
                #endif
            }
        }
    }

    /// 광고를 띄우고, 끝까지 봐서 보상 조건을 채웠으면 광고가 닫힌 뒤 onReward 를 부른다
    /// (광고가 떠 있는 동안 다른 화면을 열면 안 열리므로 닫힌 뒤에 부름).
    /// 준비된 광고가 없으면 false (부른 쪽이 다른 길로 안내).
    @discardableResult
    func show(onReward: @escaping @MainActor () -> Void) -> Bool {
        guard let ad, let root = AdConsentService.rootViewController else { return false }
        self.ad = nil
        earned = false
        pendingReward = onReward
        ad.fullScreenContentDelegate = self
        ad.present(from: Self.topMost(root)) { [weak self] in
            Task { @MainActor in self?.earned = true }
        }
        return true
    }

    /// 광고가 닫힘 → 보상 조건을 채웠으면 보상 주고 다음 편 불러두기
    private func finish() {
        let reward = earned ? pendingReward : nil
        earned = false
        pendingReward = nil
        reward?()
        load()
    }

    /// 시트/풀스크린 위에서 불러도 가장 위 화면에서 띄운다.
    private static func topMost(_ vc: UIViewController) -> UIViewController {
        var top = vc
        while let presented = top.presentedViewController { top = presented }
        return top
    }
}

extension RewardedAdLoader: FullScreenContentDelegate {
    nonisolated func adDidDismissFullScreenContent(_ ad: any FullScreenPresentingAd) {
        Task { @MainActor in self.finish() }
    }

    nonisolated func ad(_ ad: any FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: any Error) {
        Task { @MainActor in self.finish() }
    }
}
