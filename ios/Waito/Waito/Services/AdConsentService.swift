import Foundation
import Observation
import UIKit
import AppTrackingTransparency
import GoogleMobileAds
import UserMessagingPlatform

/// 광고를 부르기 전에 거쳐야 하는 동의 절차를 한 곳에서 관리한다.
///
/// 순서: 동의 상태 조회(매 실행) → 필요하면 동의 창(유럽 사용자에게만 뜸)
///       → 추적 권한 요청(iOS ATT) → 광고 SDK 시작.
/// 한국·미국 사용자는 창 없이 바로 통과한다. 이 순서를 어기고 광고를 먼저 부르면
/// 유럽 사용자에게 광고가 안 나가고 구글 정책 위반이 된다.
@MainActor
@Observable
final class AdConsentService {
    static let shared = AdConsentService()

    /// 광고 요청 가능 여부. 이 값이 true 가 되기 전엔 광고 슬롯이 아무것도 부르지 않는다.
    private(set) var canRequestAds = false
    /// 유럽 사용자처럼 "동의를 나중에 바꿀 입구"를 설정에 보여줘야 하는지.
    private(set) var isPrivacyOptionsRequired = false

    private var sdkStarted = false

    private init() {}

    /// 앱 시작 시 1회. 실패해도 지난번 저장된 동의 상태로 광고 가능 여부를 판단한다(구글 권장).
    func start() async {
        let parameters = RequestParameters()
        #if DEBUG
        // 시뮬레이터·디버그에선 유럽 지역으로 강제해 동의 창이 실제로 뜨는지 확인한다.
        let debug = DebugSettings()
        debug.geography = .EEA
        parameters.debugSettings = debug
        #endif

        do {
            try await ConsentInformation.shared.requestConsentInfoUpdate(with: parameters)
            try await ConsentForm.loadAndPresentIfRequired(from: Self.rootViewController)
        } catch {
            #if DEBUG
            NSLog("[Consent] 동의 절차 오류: %@", error.localizedDescription)
            #endif
        }

        isPrivacyOptionsRequired = ConsentInformation.shared.privacyOptionsRequirementStatus == .required

        if ConsentInformation.shared.canRequestAds {
            await requestTrackingAuthorizationIfNeeded()
            startAdsSDKOnce()
        }
        canRequestAds = ConsentInformation.shared.canRequestAds
    }

    /// 설정 화면의 "광고 개인정보 설정" 입구. 유럽 사용자가 동의를 바꾸는 창.
    func presentPrivacyOptions() async {
        do {
            try await ConsentForm.presentPrivacyOptionsForm(from: Self.rootViewController)
        } catch {
            #if DEBUG
            NSLog("[Consent] 개인정보 설정 창 오류: %@", error.localizedDescription)
            #endif
        }
        canRequestAds = ConsentInformation.shared.canRequestAds
    }

    /// iOS 추적 권한. 거부해도 광고는 나가고 개인 맞춤만 빠진다.
    private func requestTrackingAuthorizationIfNeeded() async {
        guard ATTrackingManager.trackingAuthorizationStatus == .notDetermined else { return }
        _ = await ATTrackingManager.requestTrackingAuthorization()
    }

    private func startAdsSDKOnce() {
        guard !sdkStarted else { return }
        sdkStarted = true
        MobileAds.shared.start()
    }

    /// 동의 창과 광고 SDK 가 화면을 띄울 때 쓰는 기준 화면.
    static var rootViewController: UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController
    }
}
