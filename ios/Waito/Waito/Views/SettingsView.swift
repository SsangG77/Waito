import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SubscriptionManager.self) private var subscription
    @Environment(TrackingService.self) private var service

    @AppStorage(TrackingService.alwaysShowKey) private var alwaysShowDI = false
    @State private var showPaywall = false

    // 버전 박스 5탭 → 비밀번호 팝업(디버그 언락). 이미 켜져 있으면 5탭으로 끄기.
    @AppStorage("debug_unlocked") private var debugUnlocked = false
    @State private var versionTapCount = 0
    @State private var showDebugPrompt = false
    @State private var debugPassword = ""

    // 디버그 토글 표시 조건: DEBUG 빌드이거나, 릴리즈에서 비번 언락된 경우
    private var showDebugTools: Bool {
        #if DEBUG
        return true
        #else
        return debugUnlocked
        #endif
    }

    @AppStorage("debug_show_dummy_data") private var showDummyData = false

    var body: some View {
        VStack(spacing: 0) {
            PixelNavBar(title: "SETTINGS", onBack: { dismiss() })

            ScrollView {
                VStack(spacing: 8) {
                    settingsRow(
                        icon: "crown.fill",
                        title: "Waito Plus",
                        subtitle: subscription.isSubscribed ? "구독 중" : "₩3,000/월"
                    )

                    alwaysShowRow

                    settingsRow(icon: "info.circle", title: "버전", subtitle: "1.0.0", showChevron: false)
                        .contentShape(Rectangle())
                        .onTapGesture { handleVersionTap() }

                    if showDebugTools {
                        dummyDataToggleRow
                        debugSubscriptionRow
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
        .background(Color.bg)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
        .overlay {
            if showDebugPrompt { debugPromptOverlay }
        }
    }

    // MARK: - 항상 노출 토글 (구독 전용 — 무료는 잠금 + 탭 시 Paywall)

    private var alwaysShowRow: some View {
        let locked = !subscription.canUseAlwaysShow

        // 중첩 Button 회피: 상태를 바꾸는 곳은 PixelToggle 한 곳뿐.
        // 행 탭(onTapGesture)은 잠금 상태에서 Paywall 을 여는 용도로만 동작한다.
        return HStack(spacing: 12) {
            Image(systemName: "pin.fill")
                .font(.system(size: 14))
                .foregroundStyle((!locked && alwaysShowDI) ? Color.pixelOrange : Color.pixelMuted)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text("항상 노출")
                        .font(pixelFont(11))
                        .foregroundStyle(locked ? Color.pixelMuted : Color.pixelText)
                    if locked {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(Color.pixelOrange)
                    }
                }
                Text(subtitleText(locked: locked))
                    .font(pixelFont(9))
                    .foregroundStyle((!locked && alwaysShowDI) ? Color.pixelOrange : Color.pixelMuted)
            }

            Spacer()

            // 구독자만 조작 가능. 무료(잠금)는 정적 visual → 탭이 아래 onTapGesture(Paywall)로 전달된다.
            PixelToggle(isOn: locked ? false : alwaysShowDI, isEnabled: !locked) {
                alwaysShowDI.toggle()
                Task { await service.setAlwaysShow(alwaysShowDI) }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .pixelBox(
            border: (!locked && alwaysShowDI) ? Color.pixelOrange.opacity(0.5) : Color.pixelBorder,
            bg: Color.pixelSurface,
            lineWidth: 1.5,
            notch: 4
        )
        .opacity(locked ? 0.6 : 1)
        .contentShape(Rectangle())
        .onTapGesture {
            // 잠금일 때만 의미 있음. 구독 상태에선 토글이 직접 처리한다.
            if locked { showPaywall = true }
        }
    }

    private func subtitleText(locked: Bool) -> String {
        if locked { return "Waito Plus 전용 — 배송 없어도 트럭 표시" }
        return alwaysShowDI ? "ON — 배송 없어도 트럭 표시 중" : "OFF — 배송 중일 때만 표시"
    }

    // MARK: - 일반 행

    private func settingsRow(icon: String, title: String, subtitle: String, showChevron: Bool = true) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(Color.pixelOrange)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(title.uppercased())
                    .font(pixelFont(11))
                    .foregroundStyle(Color.pixelText)
                Text(subtitle)
                    .font(pixelFont(9))
                    .foregroundStyle(Color.pixelMuted)
            }

            Spacer()

            if showChevron {
                Text(">")
                    .font(pixelFont(10))
                    .foregroundStyle(Color.pixelMuted)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .pixelBox(border: Color.pixelBorder, bg: Color.pixelSurface, lineWidth: 1.5, notch: 4)
    }

    // MARK: - 디버그 언락 (버전 5탭 → 비밀번호 970719)

    private func handleVersionTap() {
        versionTapCount += 1
        if versionTapCount >= 5 {
            versionTapCount = 0
            if debugUnlocked {
                disableDebugUnlock()       // 이미 켜져 있으면 5탭으로 끄기(비번 불필요)
            } else {
                debugPassword = ""
                showDebugPrompt = true     // 꺼져 있으면 비밀번호 팝업
            }
        }
    }

    private func submitDebugPassword() {
        if debugPassword == "970719" {
            enableDebugUnlock()
        }
        debugPassword = ""
        showDebugPrompt = false
    }

    /// 디버그 언락 ON — TEST DATA/DEBUG SUBSCRIPTION 토글 노출 + 유료 전체 해제(항상 노출 토글 잠금 해제 포함, 릴리즈에서도).
    /// 더미 택배 표시는 강제로 켜지 않고 사용자가 노출된 TEST DATA 토글로 직접 켠다.
    private func enableDebugUnlock() {
        debugUnlocked = true
        subscription.setSubscribed(true)
        Task { await service.reconcileAmbientActivity() }
    }

    /// 디버그 언락 OFF — 더미/유료/항상노출 원복 (버전 5탭 재실행)
    private func disableDebugUnlock() {
        debugUnlocked = false
        UserDefaults.standard.set(false, forKey: "debug_show_dummy_data")
        subscription.setSubscribed(false)
        Task { await service.reconcileAmbientActivity() }
    }

    private var debugPromptOverlay: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture {
                    showDebugPrompt = false
                    debugPassword = ""
                }

            VStack(spacing: 16) {
                Text("DEBUG MODE")
                    .font(pixelFont(13))
                    .foregroundStyle(Color.pixelOrange)
                PixelTextField(label: "PASSWORD", text: $debugPassword)
                HStack(spacing: 10) {
                    PixelButton(title: "CANCEL") {
                        showDebugPrompt = false
                        debugPassword = ""
                    }
                    PixelButton(title: "OK") { submitDebugPassword() }
                }
            }
            .padding(20)
            .pixelBox(border: Color.pixelBorder, bg: Color.pixelSurface, lineWidth: 1.5, notch: 4)
            .padding(.horizontal, 40)
        }
    }

    // MARK: - 디버그 테스트 데이터 토글 (DEBUG 빌드 또는 비번 언락 시 표시)

    private var dummyDataToggleRow: some View {
        Button {
            showDummyData.toggle()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "ladybug.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(showDummyData ? Color.pixelOrange : Color.pixelMuted)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 3) {
                    Text("TEST DATA")
                        .font(pixelFont(11))
                        .foregroundStyle(Color.pixelText)
                    Text(showDummyData ? "ON — 더미 택배 표시 중" : "OFF")
                        .font(pixelFont(9))
                        .foregroundStyle(showDummyData ? Color.pixelOrange : Color.pixelMuted)
                }

                Spacer()

                PixelToggle(isOn: showDummyData) { showDummyData.toggle() }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .pixelBox(
                border: showDummyData ? Color.pixelOrange.opacity(0.5) : Color.pixelBorder,
                bg: Color.pixelSurface,
                lineWidth: 1.5,
                notch: 4
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - 디버그: 구독 상태 토글 (켜면 모든 잠금 해제 — 트럭 부품 + 항상 노출)

    private var debugSubscriptionRow: some View {
        Button {
            subscription.toggleSubscription()
            Task { await service.reconcileAmbientActivity() }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: subscription.isSubscribed ? "crown.fill" : "crown")
                    .font(.system(size: 14))
                    .foregroundStyle(subscription.isSubscribed ? Color.pixelOrange : Color.pixelMuted)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 3) {
                    Text("DEBUG SUBSCRIPTION")
                        .font(pixelFont(11))
                        .foregroundStyle(Color.pixelText)
                    Text(subscription.isSubscribed ? "ON — 구독 상태(모든 잠금 해제)" : "OFF — 무료")
                        .font(pixelFont(9))
                        .foregroundStyle(subscription.isSubscribed ? Color.pixelOrange : Color.pixelMuted)
                }

                Spacer()

                PixelToggle(isOn: subscription.isSubscribed) {
                    subscription.toggleSubscription()
                    Task { await service.reconcileAmbientActivity() }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .pixelBox(
                border: subscription.isSubscribed ? Color.pixelOrange.opacity(0.5) : Color.pixelBorder,
                bg: Color.pixelSurface,
                lineWidth: 1.5,
                notch: 4
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
    .environment(SubscriptionManager())
    .environment(TrackingService())
}
