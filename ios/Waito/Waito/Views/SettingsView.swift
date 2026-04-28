import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SubscriptionManager.self) private var subscription

    #if DEBUG
    @Environment(TrackingService.self) private var service
    @State private var isDemoActive = false
    @State private var showDemoError = false
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
                    debugDemoRow
                    #endif
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
        .background(Color.bg)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        #if DEBUG
        .onChange(of: service.error) { _, newValue in
            showDemoError = newValue != nil
        }
        .pixelAlert(
            title: "오류",
            message: service.error ?? "",
            isPresented: $showDemoError
        ) { service.clearError() }
        #endif
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

    // MARK: - 디버그 데모 토글

    #if DEBUG
    private var debugDemoRow: some View {
        Button {
            isDemoActive.toggle()
            Task {
                if isDemoActive {
                    await service.startDemoLiveActivity()
                } else {
                    await service.stopDemoLiveActivity()
                }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 14))
                    .foregroundStyle(isDemoActive ? Color.pixelOrange : Color.pixelMuted)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 3) {
                    Text("DYNAMIC ISLAND DEMO")
                        .font(pixelFont(11))
                        .foregroundStyle(Color.pixelText)
                    Text(isDemoActive ? "ON — 트럭이 달리는 중" : "OFF")
                        .font(pixelFont(9))
                        .foregroundStyle(isDemoActive ? Color.pixelOrange : Color.pixelMuted)
                }

                Spacer()

                Text(isDemoActive ? "[ON]" : "[OFF]")
                    .font(pixelFont(9))
                    .foregroundStyle(isDemoActive ? Color.pixelOrange : Color.pixelMuted)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .pixelBox(
                border: isDemoActive ? Color.pixelOrange.opacity(0.5) : Color.pixelBorder,
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
