import SwiftUI

struct TruckCustomizeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SubscriptionManager.self) private var subscription
    @Environment(TrackingService.self) private var service
    @Bindable private var store = TruckConfigStore.shared

    @State private var showSubscriptionAlert = false
    @State private var isDemoActive = false

    /// 미리보기용 임시 조합. 잠금 요소도 자유롭게 골라 미리 볼 수 있고,
    /// "저장하기"를 눌러야 store.config 에 커밋된다(= Live Activity/서버 갱신).
    @State private var draft = TruckConfigStore.shared.config

    var body: some View {
        VStack(spacing: 0) {
            PixelNavBar(title: "MY TRUCK", onBack: { dismiss() })

            ScrollView {
                VStack(spacing: 20) {
                    previewSection
                    dynamicIslandDemoButton
                    catalogSection(title: "CAB", items: TruckCab.allCases, selected: draft.cab) { cab in
                        CatalogTruckView(cab: cab, truckBody: draft.body, wheels: draft.wheelType, size: 56)
                    } onSelect: { cab in
                        draft.cab = cab
                    } requiresPlus: { $0.requiresPlus }

                    catalogSection(title: "BODY", items: TruckBody.allCases, selected: draft.body) { body in
                        CatalogTruckView(cab: draft.cab, truckBody: body, wheels: draft.wheelType, size: 56)
                    } onSelect: { body in
                        draft.body = body
                    } requiresPlus: { $0.requiresPlus }

                    catalogSection(title: "WHEELS", items: TruckWheelType.allCases, selected: draft.wheelType) { wheels in
                        CatalogTruckView(cab: draft.cab, truckBody: draft.body, wheels: wheels, size: 56)
                    } onSelect: { wheels in
                        draft.wheelType = wheels
                    } requiresPlus: { $0.requiresPlus }

                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
        .background(Color.bg)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom) { saveBar }
        .onChange(of: store.config) {
            Task {
                await service.pushTruckConfig()            // 실행 중인 Activity 즉시 반영
                await service.refreshPushToStartConfig()   // 8h 재시작 시 쓰일 서버 측 트럭 설정도 갱신
            }
        }
        .fullScreenCover(isPresented: $showSubscriptionAlert) {
            PlusPaywallView {
                // TODO: 실제 StoreKit 구매 연결 (.storekit 설정 후 Product.purchase / SubscriptionStoreView)
                #if DEBUG
                if !subscription.isSubscribed { subscription.toggleSubscription() }
                #endif
                // 구독 직후, 미리보기 중이던 조합을 저장(커밋)
                if subscription.isSubscribed { store.config = draft }
            }
        }
    }

    // MARK: - 저장 바 (하단 고정) — 유료 부품 포함 시 비구독이면 Paywall

    private var draftRequiresPlus: Bool {
        draft.cab.requiresPlus || draft.body.requiresPlus || draft.wheelType.requiresPlus
    }

    private var hasChanges: Bool { draft != store.config }

    private func handleSave() {
        // 유료 부품이 하나라도 포함됐고 비구독이면 → 구독 요청 모달
        if draftRequiresPlus && !subscription.isSubscribed {
            showSubscriptionAlert = true
            return
        }
        store.config = draft   // 커밋 → onChange 가 Live Activity/서버 설정 갱신
    }

    private var saveBar: some View {
        // 외형은 유료 여부와 무관하게 동일. 변경 유무로만 강조/비활성 구분.
        Button(action: handleSave) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark")
                    .font(.system(size: 13))
                Text("저장하기_")
                    .font(pixelFont(12))
                Spacer()
            }
            .foregroundStyle(hasChanges ? .black : Color.pixelMuted)
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
            .pixelBox(
                border: Color.pixelBorder,
                bg: hasChanges ? Color.pixelOrange : Color.pixelSurface,
                lineWidth: 1.5, notch: 4
            )
        }
        .buttonStyle(.plain)
        .disabled(!hasChanges)
        .opacity(hasChanges ? 1 : 0.45)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(Color.bg)
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
                cab: draft.cab,
                truckBody: draft.body,
                wheels: draft.wheelType,
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
                            // 잠금 요소도 미리보기로 선택 가능 — 게이팅은 "저장하기"에서.
                            onTap: { onSelect(item) }
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

}

#Preview {
    NavigationStack {
        TruckCustomizeView()
    }
    .environment(SubscriptionManager())
    .environment(TrackingService())
}
