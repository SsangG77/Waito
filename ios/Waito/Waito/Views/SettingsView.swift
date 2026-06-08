import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SubscriptionManager.self) private var subscription

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

                    settingsRow(icon: "info.circle", title: "버전", subtitle: "1.0.0")

                    #if DEBUG
                    dummyDataToggleRow
                    #endif
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
        .background(Color.bg)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
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
    #endif
}

#Preview {
    NavigationStack {
        SettingsView()
    }
    .environment(SubscriptionManager())
    .environment(TrackingService())
}
