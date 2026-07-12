import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SubscriptionManager.self) private var subscription
    @Environment(TrackingService.self) private var service

    @AppStorage(TrackingService.alwaysShowKey) private var alwaysShowDI = false
    @State private var showPaywall = false
    /// Waito Plus 행 탭 시 여는 풀스크린 페이월(구독 여부와 무관하게 노출)
    @State private var showPlusPaywall = false

    // 버전 박스 5탭 → 비밀번호 팝업 → 관리자 모드 ON. 켜진 상태에서 5탭 → OFF.
    // 관리자 모드 = 디버그 토글(TEST DATA / DEBUG SUBSCRIPTION)만 노출. 더미·구독을 자동으로 켜지 않는다.
    @AppStorage("admin_mode") private var adminMode = false
    @State private var versionTapCount = 0
    @State private var showDebugPrompt = false
    @State private var debugPassword = ""

    // 디버그 토글 표시 조건: DEBUG 빌드이거나, 릴리즈에서 관리자 모드 ON
    private var showDebugTools: Bool {
        #if DEBUG
        return true
        #else
        return adminMode
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
                    .contentShape(Rectangle())
                    .onTapGesture { showPlusPaywall = true }   // 구독 중이어도 페이월 노출(CTA만 "구독중" 비활성)
                    .accessibilityIdentifier("settings_waito_plus_row")

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
        .onChange(of: showDummyData) { _, isOn in
            // 토글 OFF 시 LA/DI 에 남은 더미 택배 즉시 제거 (disableAdminMode 경로 포함)
            if !isOn { Task { await service.purgeDummyFromLiveActivity() } }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
                .environment(subscription)   // 시트 환경 명시 재주입
        }
        .fullScreenCover(isPresented: $showPlusPaywall) {
            PlusPaywallView()
                .environment(subscription)   // 커버 환경 명시 재주입(자동 전파 보장 안 됨)
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
            if adminMode {
                disableAdminMode()         // 켜져 있으면 5탭으로 끄기(비번 불필요)
            } else {
                debugPassword = ""
                showDebugPrompt = true     // 꺼져 있으면 비밀번호 팝업
            }
        }
    }

    private func submitDebugPassword() {
        if debugPassword == "970719" {
            adminMode = true   // 관리자 모드 ON — 토글만 노출. 더미·구독은 사용자가 토글로 직접 제어
        }
        debugPassword = ""
        showDebugPrompt = false
    }

    /// 관리자 모드 OFF — 토글 숨김 + 토글로 켜뒀던 효과(더미/디버그 구독) 원복. 실제 구독은 건드리지 않음.
    private func disableAdminMode() {
        adminMode = false
        showDummyData = false                 // 더미 표시 끔(토글이 숨겨지므로 잔존 방지)
        subscription.setDebugUnlocked(false)  // 디버그 구독 해제
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
            subscription.toggleDebugUnlocked()
            Task { await service.reconcileAmbientActivity() }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: subscription.isDebugUnlocked ? "crown.fill" : "crown")
                    .font(.system(size: 14))
                    .foregroundStyle(subscription.isDebugUnlocked ? Color.pixelOrange : Color.pixelMuted)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 3) {
                    Text("DEBUG SUBSCRIPTION")
                        .font(pixelFont(11))
                        .foregroundStyle(Color.pixelText)
                    Text(subscription.isDebugUnlocked ? "ON — 디버그 언락(모든 잠금 해제)" : "OFF — 무료")
                        .font(pixelFont(9))
                        .foregroundStyle(subscription.isDebugUnlocked ? Color.pixelOrange : Color.pixelMuted)
                }

                Spacer()

                PixelToggle(isOn: subscription.isDebugUnlocked) {
                    subscription.toggleDebugUnlocked()
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
