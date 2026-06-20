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

    // 포인트 해제 흐름 상태
    @State private var showUnlockConfirm = false
    @State private var showInsufficient = false
    @State private var pendingUnlock: [String] = []   // 해제할 부품 rawValue
    @State private var unlockCost = 0

    /// 셀 잠금 표시 종류
    private enum CellLock { case none, plus, point }

    var body: some View {
        VStack(spacing: 0) {
            PixelNavBar(title: "MY TRUCK", onBack: { dismiss() })

            ScrollView {
                VStack(spacing: 20) {
                    previewSection
                    pointBar
                    dynamicIslandDemoButton

                    catalogSection(title: "CAB", items: TruckCab.allCases, selected: draft.cab) { cab in
                        CatalogTruckView(cab: cab, truckBody: draft.body, wheels: draft.wheelType, size: 56)
                    } onSelect: { cab in
                        draft.cab = cab
                    } lock: { cellLock(tier: $0.tier, raw: $0.rawValue) }

                    catalogSection(title: "BODY", items: TruckBody.allCases, selected: draft.body) { body in
                        CatalogTruckView(cab: draft.cab, truckBody: body, wheels: draft.wheelType, size: 56)
                    } onSelect: { body in
                        draft.body = body
                    } lock: { cellLock(tier: $0.tier, raw: $0.rawValue) }

                    catalogSection(title: "WHEELS", items: TruckWheelType.allCases, selected: draft.wheelType) { wheels in
                        CatalogTruckView(cab: draft.cab, truckBody: draft.body, wheels: wheels, size: 56)
                    } onSelect: { wheels in
                        draft.wheelType = wheels
                    } lock: { cellLock(tier: $0.tier, raw: $0.rawValue) }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
        .background(Color.bg)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom) { saveBar }
        .task { await service.loadDeviceProgress() }
        .onChange(of: store.config) {
            Task {
                await service.pushTruckConfig()            // 실행 중인 Activity 즉시 반영
                await service.refreshPushToStartConfig()   // 8h 재시작 시 쓰일 서버 측 트럭 설정도 갱신
            }
        }
        .pixelConfirm(
            title: "포인트로 해제",
            message: "선택한 부품 \(pendingUnlock.count)개를 \(unlockCost)P로 해제하고 저장할까요?\n보유 \(service.pointBalance)P",
            confirmTitle: "해제",
            cancelTitle: "취소",
            isPresented: $showUnlockConfirm
        ) {
            confirmUnlockAndSave()
        }
        .pixelConfirm(
            title: "포인트 부족",
            message: "필요 \(unlockCost)P / 보유 \(service.pointBalance)P\n배송을 완료하면 포인트가 쌓여요. Waito Plus로 한 번에 풀 수도 있어요.",
            confirmTitle: "Plus 보기",
            cancelTitle: "닫기",
            isPresented: $showInsufficient
        ) {
            showSubscriptionAlert = true
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

    // MARK: - 포인트 표시 바

    private var pointBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "star.fill")
                .font(.system(size: 12))
                .foregroundStyle(Color.pixelOrange)
            Text("\(service.pointBalance) P")
                .font(pixelFont(12))
                .foregroundStyle(Color.pixelText)
            Spacer()
            Text("배송완료 1건 = 1P · 해제 \(pointUnlockCost)P")
                .font(pixelFont(8))
                .foregroundStyle(Color.pixelMuted)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .pixelBox(border: Color.pixelBorder, bg: Color.pixelSurface, lineWidth: 1.5, notch: 4)
    }

    // MARK: - 잠금 판정

    /// 셀에 표시할 잠금 종류
    private func cellLock(tier: PartTier, raw: String) -> CellLock {
        if tier == .free || subscription.isSubscribed { return .none }
        if tier == .pointUnlockable { return service.isUnlocked(raw) ? .none : .point }
        return .plus
    }

    // MARK: - 저장 / 해제

    private struct DraftPart { let raw: String; let tier: PartTier }
    private var draftParts: [DraftPart] {
        [DraftPart(raw: draft.cab.rawValue, tier: draft.cab.tier),
         DraftPart(raw: draft.body.rawValue, tier: draft.body.tier),
         DraftPart(raw: draft.wheelType.rawValue, tier: draft.wheelType.tier)]
    }

    /// 지금 바로 저장 가능한 부품인지 (무료 / 구독 / 포인트 해제됨)
    private func isUsable(_ p: DraftPart) -> Bool {
        if p.tier == .free { return true }
        if subscription.isSubscribed { return true }
        if p.tier == .pointUnlockable { return service.isUnlocked(p.raw) }
        return false
    }

    private var hasChanges: Bool { draft != store.config }

    private func handleSave() {
        let unusable = draftParts.filter { !isUsable($0) }
        if unusable.isEmpty {
            store.config = draft   // 커밋 → onChange 가 Live Activity/서버 설정 갱신
            return
        }
        // Plus 전용 부품이 끼어 있으면 포인트로 못 풀므로 구독 유도
        if unusable.contains(where: { $0.tier == .plusOnly }) {
            showSubscriptionAlert = true
            return
        }
        // 남은 건 모두 포인트 해제 대상 — 비용 계산
        let cost = unusable.count * pointUnlockCost
        unlockCost = cost
        pendingUnlock = unusable.map { $0.raw }
        if service.pointBalance >= cost {
            showUnlockConfirm = true
        } else {
            showInsufficient = true
        }
    }

    private func confirmUnlockAndSave() {
        let parts = pendingUnlock
        Task {
            for raw in parts {
                _ = await service.unlockPart(raw)
            }
            // 전부 해제 성공하면 커밋
            if parts.allSatisfy({ service.isUnlocked($0) }) {
                store.config = draft
            }
            pendingUnlock = []
        }
    }

    private var saveBar: some View {
        // 외형은 등급과 무관하게 동일. 변경 유무로만 강조/비활성 구분.
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
        lock: @escaping (T) -> CellLock
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(pixelFont(10))
                .foregroundStyle(Color.pixelOrange)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(items, id: \.self) { item in
                        catalogCell(
                            isSelected: item == selected,
                            lock: lock(item),
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

    private func catalogCell<V: View>(
        isSelected: Bool,
        lock: CellLock,
        thumbnail: () -> V,
        onTap: @escaping () -> Void
    ) -> some View {
        Button(action: onTap) {
            ZStack {
                Color.black

                thumbnail()

                if lock != .none {
                    Color.black.opacity(0.5)
                    switch lock {
                    case .plus:
                        // Plus 전용
                        Image(systemName: "crown.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.pixelOrange)
                    case .point:
                        // 포인트로 해제 가능 — 비용 표시
                        VStack(spacing: 2) {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(Color.pixelMuted)
                            Text("\(pointUnlockCost)P")
                                .font(pixelFont(8))
                                .foregroundStyle(Color.pixelOrange)
                        }
                    case .none:
                        EmptyView()
                    }
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
