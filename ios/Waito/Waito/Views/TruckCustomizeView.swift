import SwiftUI

struct TruckCustomizeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SubscriptionManager.self) private var subscription
    @Environment(TrackingService.self) private var service
    @Bindable private var store = TruckConfigStore.shared

    @State private var showSubscriptionAlert = false
    @State private var isDemoActive = false

    var body: some View {
        VStack(spacing: 0) {
            PixelNavBar(title: "MY TRUCK", onBack: { dismiss() })

            ScrollView {
                VStack(spacing: 20) {
                    previewSection
                    dynamicIslandDemoButton
                    catalogSection(title: "CAB", items: TruckCab.allCases, selected: store.config.cab) { cab in
                        CatalogTruckView(cab: cab, truckBody:store.config.body, wheels: store.config.wheelType, size: 56)
                    } onSelect: { cab in
                        store.config.cab = cab
                    } requiresPlus: { $0.requiresPlus }

                    catalogSection(title: "BODY", items: TruckBody.allCases, selected: store.config.body) { body in
                        CatalogTruckView(cab: store.config.cab, truckBody:body, wheels: store.config.wheelType, size: 56)
                    } onSelect: { body in
                        store.config.body = body
                    } requiresPlus: { $0.requiresPlus }

                    catalogSection(title: "WHEELS", items: TruckWheelType.allCases, selected: store.config.wheelType) { wheels in
                        CatalogTruckView(cab: store.config.cab, truckBody:store.config.body, wheels: wheels, size: 56)
                    } onSelect: { wheels in
                        store.config.wheelType = wheels
                    } requiresPlus: { $0.requiresPlus }

                    #if DEBUG
                    debugSubscriptionSection
                    #endif
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
        .background(Color.bg)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: store.config) {
            Task { await service.pushTruckConfig() }
        }
        .pixelAlert(
            title: "Waito Plus",
            message: "이 옵션은 Waito Plus 구독이 필요해요.\n월 ₩2,900 / 연 ₩19,900",
            isPresented: $showSubscriptionAlert
        )
    }

    // MARK: - Dynamic Island 데모 버튼

    private var dynamicIslandDemoButton: some View {
        Button {
            Task {
                if isDemoActive {
                    await service.stopDemoLiveActivity()
                    isDemoActive = false
                } else {
                    await service.startDemoLiveActivity()
                    isDemoActive = true
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isDemoActive ? "dot.radiowaves.left.and.right" : "dot.radiowaves.left.and.right.slash")
                    .font(.system(size: 13))
                    .foregroundStyle(isDemoActive ? Color.pixelOrange : Color.pixelMuted)
                Text(isDemoActive ? "DYNAMIC ISLAND ON_" : "PREVIEW ON ISLAND_")
                    .font(pixelFont(11))
                    .foregroundStyle(isDemoActive ? Color.pixelOrange : Color.pixelText)
                Spacer()
                Text(isDemoActive ? "[ON]" : "[OFF]")
                    .font(pixelFont(9))
                    .foregroundStyle(isDemoActive ? Color.pixelOrange : Color.pixelMuted)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .pixelBox(
                border: isDemoActive ? Color.pixelOrange.opacity(0.5) : Color.pixelBorder,
                bg: isDemoActive ? Color.pixelOrange.opacity(0.06) : Color.pixelSurface,
                lineWidth: 1.5, notch: 4
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - 미리보기

    private var previewSection: some View {
        ZStack {
            Color.black
                .clipShape(NotchedRectangle(notch: 8))
            CatalogTruckView(
                cab: store.config.cab,
                truckBody: store.config.body,
                wheels: store.config.wheelType,
                size: 140
            )
        }
        .frame(height: 160)
        .overlay(
            PixelBorderShape(cornerGap: 8)
                .stroke(Color.pixelBorder, lineWidth: 1.5)
        )
    }

    // MARK: - 카탈로그 섹션 (제네릭)

    private func catalogSection<T: Hashable, V: View>(
        title: String,
        items: [T],
        selected: T,
        thumbnail: @escaping (T) -> V,
        onSelect: @escaping (T) -> Void,
        requiresPlus: @escaping (T) -> Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(pixelFont(10))
                .foregroundStyle(Color.pixelOrange)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(items, id: \.self) { item in
                        catalogCell(
                            item: item,
                            isSelected: item == selected,
                            locked: requiresPlus(item) && !subscription.isSubscribed,
                            thumbnail: { thumbnail(item) },
                            onTap: {
                                if requiresPlus(item) && !subscription.isSubscribed {
                                    showSubscriptionAlert = true
                                } else {
                                    onSelect(item)
                                }
                            }
                        )
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func catalogCell<T, V: View>(
        item: T,
        isSelected: Bool,
        locked: Bool,
        thumbnail: () -> V,
        onTap: @escaping () -> Void
    ) -> some View {
        Button(action: onTap) {
            ZStack {
                Color.black

                thumbnail()

                if locked {
                    Color.black.opacity(0.5)
                    Image(systemName: "lock.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.pixelMuted)
                }
            }
            .frame(width: 72, height: 54)
            .pixelBox(
                border: isSelected ? Color.pixelOrange : Color.pixelBorder,
                bg: Color.pixelSurface,
                lineWidth: isSelected ? 2 : 1.5,
                notch: 3
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - 디버그 구독 토글

    #if DEBUG
    private var debugSubscriptionSection: some View {
        VStack(spacing: 8) {
            Rectangle()
                .fill(Color.pixelBorder)
                .frame(height: 1)
            Button {
                subscription.toggleSubscription()
            } label: {
                HStack {
                    Image(systemName: subscription.isSubscribed ? "checkmark.circle.fill" : "circle")
                    Text(subscription.isSubscribed ? "구독 중 (디버그)" : "구독 안 함 (디버그)")
                }
                .font(pixelFont(9))
                .foregroundStyle(Color.pixelMuted)
            }
        }
    }
    #endif
}

#Preview {
    NavigationStack {
        TruckCustomizeView()
    }
    .environment(SubscriptionManager())
    .environment(TrackingService())
}
