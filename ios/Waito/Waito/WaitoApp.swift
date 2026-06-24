//
//  WaitoApp.swift
//  Waito
//
//  Created by 김무경 on 3/17/26.
//

import SwiftUI
import UIKit
import UserNotifications

@main
struct WaitoApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var trackingService = TrackingService()
    @State private var subscriptionManager = SubscriptionManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(trackingService)
                .environment(subscriptionManager)
                .preferredColorScheme(.dark)
                .task { await subscriptionManager.start() }   // 상품 로드 + 구독 권한 확인 + 트랜잭션 관찰
        }
    }
}

// MARK: - AppDelegate (표준 원격알림 등록/수신)
// 모든 택배 상태 변경 시 서버가 보내는 일반 푸시 배너를 받기 위한 표준 APNs 등록.
// (Live Activity 푸시와는 별개의 토큰/토픽)
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        // 알림 권한 요청 → 허용 시 원격알림 등록 (토큰은 didRegister 콜백으로 옴)
        Task { @MainActor in
            let granted = (try? await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            if granted {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
        return true
    }

    // 앱이 활성화될 때 권한이 이미 허용돼 있으면 재등록 → 캐시 토큰이 didRegister 로 다시 와
    // 서버 동기화가 갱신된다. (사용자가 설정에서 나중에 알림을 켠 케이스 복구)
    func applicationDidBecomeActive(_ application: UIApplication) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else { return }
            Task { @MainActor in UIApplication.shared.registerForRemoteNotifications() }
        }
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        // 디바이스(서버) 등록이 끝나 Keychain 에 device 토큰이 생길 때까지 잠시 재시도하며 올린다.
        // (권한 다이얼로그/디바이스 등록 타이밍과 무관하게 결국 등록되도록 하는 단일 경로)
        Task {
            for _ in 0..<10 {
                if let device = Keychain.read(TrackingService.deviceTokenKeychainKey) {
                    try? await APIClient.shared.registerAPNsToken(deviceToken: device, apnsToken: hex)
                    return
                }
                try? await Task.sleep(nanoseconds: 700_000_000)  // ~0.7s
            }
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        #if DEBUG
        // Push Notifications capability(aps-environment entitlement) 미설정 시 여기로 옴
        print("[APNs] 원격알림 등록 실패: \(error.localizedDescription)")
        #endif
    }

    // 앱이 포그라운드일 때도 배너를 표시
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
