import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SubscriptionManager.self) private var subscription
    @Environment(TrackingService.self) private var service

    @AppStorage(TrackingService.alwaysShowKey) private var alwaysShowDI = false
    @State private var showPaywall = false

    #if DEBUG
    @AppStorage("debug_show_dummy_data") private var showDummyData = false
    #endif

    var body: some View {
        VStack(spacing: 0) {
            PixelNavBar(title: "SETTINGS", onBack: { dismiss() })

            ScrollView {
                VStack(spacing: 8) {
                    settingsRow(
                        icon: "crown.fill",
                        title: "Waito Plus",
                        subtitle: subscription.isSubscribed ? "구독 중" : "₩2,900/월 · ₩19,900/년"
                    )

                    alwaysShowRow

                    settingsRow(icon: "info.circle", title: "버전", subtitle: "1.0.0")

                    #if DEBUG
                    dummyDataToggleRow
                    debugSubscriptionRow
                    #endif
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

    private func settingsRow(icon: String, title: String, subtitle: String) -> some View {
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

            Text(">")
                .font(pixelFont(10))
                .foregroundStyle(Color.pixelMuted)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .pixelBox(border: Color.pixelBorder, bg: Color.pixelSurface, lineWidth: 1.5, notch: 4)
    }

    // MARK: - 디버그 테스트 데이터 토글

    #if DEBUG
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
    #endif
}

#Preview {
    NavigationStack {
        SettingsView()
    }
    .environment(SubscriptionManager())
    .environment(TrackingService())
}
