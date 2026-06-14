import SwiftUI

// MARK: - 정렬 기준

enum DeliverySortOrder: String, CaseIterable {
    case arrival      // 도착 임박순
    case updated      // 최근 업데이트순
    case registered   // 등록순

    var label: String {
        switch self {
        case .arrival:    return "도착임박순"
        case .updated:    return "업데이트순"
        case .registered: return "등록순"
        }
    }
}

// MARK: - 택배 목록

struct DeliveryListView: View {
    @Environment(TrackingService.self) private var service
    @Environment(SubscriptionManager.self) private var subscription

    @State private var showAddForm = false
    @State private var showError = false
    @State private var showSubscriptionAlert = false
    @State private var showPaywall = false
    @State private var showNotFoundConfirm = false
    @State private var notFoundMessage = ""
    /// 첫 택배 추가 직후 띄우는 업셀 페이월
    @State private var showFirstAddPaywall = false
    /// 첫 추가 페이월을 이미 보여줬는지 (평생 1회)
    @AppStorage("has_shown_first_add_paywall") private var hasShownFirstAddPaywall = false
    /// 삭제 확인 대상 / 표시 여부
    @State private var pendingDeleteTracking: TrackingListItem?
    @State private var showDeleteConfirm = false
    /// 삭제 버튼이 열린 행 (한 번에 하나만)
    @State private var openRowId: Int?
    /// 정렬 기준 (기본: 도착 임박순, 사용자 선택 영구 저장)
    @AppStorage("delivery_sort_order") private var sortOrderRaw = DeliverySortOrder.arrival.rawValue
    private var sortOrder: DeliverySortOrder { DeliverySortOrder(rawValue: sortOrderRaw) ?? .arrival }

    #if DEBUG
    @AppStorage("debug_show_dummy_data") private var showDummyData = false
    #endif

    // 입력 폼 상태
    @State private var newTrackingNumber = ""
    @State private var newCarrierId = ""
    @State private var newItemName = ""
    @State private var newMemo = ""
    @State private var isSubmitting = false
    /// 편집 중인 택배 id (nil 이면 신규 추가 모드). 설정되면 폼이 EDIT 모드로 동작.
    @State private var editingTrackingId: Int?
    /// 방금 추가돼 한 번 바운스로 강조할 행 id
    @State private var justAddedId: Int?

    var body: some View {
        listContent
            .onChange(of: service.error) { _, newValue in showError = newValue != nil }
            .pixelAlert(
                title: "오류",
                message: service.error ?? "",
                isPresented: $showError
            ) { service.clearError() }
            .pixelAlert(
                title: "Waito Plus",
                message: "무료 사용자는 Live Activity를 1개까지 등록할 수 있어요.\nWaito Plus 구독 시 2개까지 가능합니다.",
                isPresented: $showSubscriptionAlert
            ) {
                showPaywall = true
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
            .fullScreenCover(isPresented: $showFirstAddPaywall) {
                PlusPaywallView {
                    // TODO: 실제 StoreKit 구매 연결 (.storekit 설정 후 Product.purchase)
                    #if DEBUG
                    if !subscription.isSubscribed { subscription.toggleSubscription() }
                    #endif
                }
            }
            .pixelConfirm(
                title: "운송장 확인",
                message: notFoundMessage,
                confirmTitle: "그래도 추가",
                cancelTitle: "취소",
                isPresented: $showNotFoundConfirm
            ) {
                submit(force: true)
            }
            .pixelConfirm(
                title: "택배 삭제",
                message: deleteConfirmMessage,
                confirmTitle: "삭제",
                cancelTitle: "취소",
                isPresented: $showDeleteConfirm
            ) {
                performDelete()
            }
            .task {
                if service.carriers.isEmpty {
                    await service.loadCarriers()
                }
            }
    }

    /// 목록에 표시할 택배. 디버그 테스트 토글이 켜지면 더미 데이터를 보여준다.
    private var displayedTrackings: [TrackingListItem] {
        #if DEBUG
        if showDummyData { return sortTrackings(TrackingService.dummyTrackings) }
        #endif
        return sortTrackings(service.trackings)
    }

    private func sortTrackings(_ items: [TrackingListItem]) -> [TrackingListItem] {
        switch sortOrder {
        case .arrival:
            // 미완료를 위로, 그 안에서 진행도 높은(곧 도착) 순. 완료는 아래로.
            return items.sorted { a, b in
                if a.currentStatus.isCompleted != b.currentStatus.isCompleted {
                    return !a.currentStatus.isCompleted
                }
                if a.currentTValue != b.currentTValue {
                    return a.currentTValue > b.currentTValue
                }
                return a.createdAt > b.createdAt
            }
        case .updated:
            // 마지막 변경(updated_at)이 최신인 순. 없으면 등록일로 대체.
            return items.sorted { ($0.updatedAt ?? $0.createdAt) > ($1.updatedAt ?? $1.createdAt) }
        case .registered:
            return items.sorted { $0.createdAt > $1.createdAt }
        }
    }

    private var listContent: some View {
        VStack(spacing: 8) {
            actionButtons

            HStack {
                Spacer()
                sortBar
            }

            if showAddForm {
                inlineAddForm
                    .transition(.opacity)
            }

            ScrollView {
                if displayedTrackings.isEmpty {
                    emptyState
                        .frame(minHeight: 660)
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach(displayedTrackings) { tracking in
                            TrackingRowView(
                                tracking: tracking,
                                isLiveActive: service.isInLiveActivity(trackingNumber: tracking.trackingNumber),
                                onToggleLiveActivity: { toggleLiveActivity(for: tracking) },
                                onDelete: { requestDelete(tracking) },
                                onEdit: { startEditing(tracking) },
                                openRowId: $openRowId,
                                justAddedId: justAddedId
                            )
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .refreshable { await service.loadTrackings() }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .background(Color.bg)
    }

    // MARK: - 빈 상태 (택배 없음 → 달리는 트럭)

    /// 택배가 하나도 없을 때, 사용자가 고른 트럭이 화면 가운데서 "달리는" 효과.
    /// 인앱 화면이라 RunningTruckView 의 연속 애니메이션이 정상 재생된다.
    /// (TruckConfigStore 는 @Observable 이라 트럭을 바꾸면 자동 갱신)
    private var emptyState: some View {
        let cfg = TruckConfigStore.shared.config
        return VStack(spacing: 6) {
            Spacer(minLength: 0)

            RunningTruckView(lineCount: 8) {
                CatalogTruckView(cab: cfg.cab, truckBody: cfg.body, wheels: cfg.wheelType, size: 96)
            }
            .frame(height: 170)

            Text("아직 택배가 없어요")
                .font(pixelFont(13))
                .foregroundStyle(Color.pixelText)
                .padding(.top, 2)

            HStack(spacing: 5) {
                Image(systemName: "chevron.up")
                    .font(.system(size: 10, weight: .bold))
                Text("위 ADD 버튼으로 택배를 추가해보세요")
                    .font(pixelFont(10))
            }
            .foregroundStyle(Color.pixelMuted)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 버튼 영역

    private var actionButtons: some View {
        VStack(spacing: 6) {
            // Option A: [⚙️] [ADD ──────>] [🚚]
            HStack(spacing: 8) {
                settingsButton
                addButton
                truckButton(wide: false)
            }

//            // Option B: [⚙️] [+] [🚚 ──────────>]
//            HStack(spacing: 8) {
//                settingsButton
//                compactAddButton
//                truckButton(wide: true)
//            }
        }
    }

    // MARK: - 정렬 선택 바

    private var sortBar: some View {
        HStack(spacing: 6) {
            ForEach(DeliverySortOrder.allCases, id: \.self) { order in
                let selected = sortOrder == order
                Button {
                    sortOrderRaw = order.rawValue
                    openRowId = nil  // 정렬 바꾸면 열린 삭제 버튼 닫기
                } label: {
                    Text(order.label)
                        .font(pixelFont(9))
                        .foregroundStyle(selected ? Color.pixelOrange : Color.pixelMuted)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .pixelBox(
                            border: selected ? Color.pixelOrange.opacity(0.6) : Color.pixelBorder,
                            bg: selected ? Color.pixelOrange.opacity(0.1) : Color.pixelSurface,
                            lineWidth: 1.5,
                            notch: 3
                        )
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    private var settingsButton: some View {
        NavigationLink(destination: SettingsView()) {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 14))
                .foregroundStyle(Color.pixelMuted)
                .frame(width: 46, height: 46)
                .pixelBox(border: Color.pixelBorder, bg: Color.pixelSurface, lineWidth: 1.5, notch: 4)
        }
        .buttonStyle(.plain)
    }

    private var compactAddButton: some View {
        Button {
            openRowId = nil  // 열려 있던 삭제 버튼 닫기
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                showAddForm.toggle()
                if !showAddForm { resetForm() }
            }
        } label: {
            Text(showAddForm ? "v" : "+")
                .font(pixelFont(14))
                .foregroundStyle(showAddForm ? Color.pixelMuted : Color.pixelText)
                .frame(width: 46, height: 46)
                .pixelBox(
                    border: showAddForm ? Color.pixelBorder : Color.pixelOrange.opacity(0.7),
                    bg: showAddForm ? Color.pixelSurface : Color.pixelOrange.opacity(0.1),
                    lineWidth: 1.5, notch: 4
                )
        }
        .buttonStyle(.plain)
    }

    private func truckButton(wide: Bool) -> some View {
        // 사용자가 선택한 트럭을 표시 (TruckConfigStore 는 @Observable 이라 변경 시 자동 갱신)
        let cfg = TruckConfigStore.shared.config
        return NavigationLink(destination: TruckCustomizeView()) {
            HStack(spacing: 6) {
                CatalogTruckView(cab: cfg.cab, truckBody: cfg.body, wheels: cfg.wheelType, size: 24)
                if wide {
                    Text("MY TRUCK_")
                        .font(pixelFont(10))
                        .foregroundStyle(Color.pixelText)
                }
            }
            .frame(maxWidth: wide ? .infinity : nil)
            .frame(width: wide ? nil : 46, height: 46)
            .pixelBox(border: Color.pixelOrange.opacity(0.5), bg: Color.pixelOrange.opacity(0.08), lineWidth: 1.5, notch: 4)
        }
        .buttonStyle(.plain)
    }

    private var addButton: some View {
        Button {
            openRowId = nil  // 열려 있던 삭제 버튼 닫기
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                showAddForm.toggle()
                if !showAddForm { resetForm() }
            }
        } label: {
            HStack(spacing: 8) {
                Text(showAddForm ? "v" : ">")
                Text(showAddForm ? "CLOSE_" : "ADD_")
            }
            .font(pixelFont(11))
            .foregroundStyle(showAddForm ? Color.pixelMuted : Color.pixelText)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .pixelBox(
                border: showAddForm ? Color.pixelBorder : Color.pixelOrange.opacity(0.7),
                bg: showAddForm ? Color.pixelSurface : Color.pixelOrange.opacity(0.1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - 인라인 입력 폼

    /// 편집 모드 여부 (운송장번호/택배사는 '신원'이라 수정 불가 → 품명/메모만 수정)
    private var isEditing: Bool { editingTrackingId != nil }

    private var inlineAddForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isEditing {
                // 운송장번호/택배사는 읽기전용으로 채워서 보여줌
                PixelTextField(label: "TRACKING NO.", text: $newTrackingNumber, disabled: true)
                PixelTextField(label: "CARRIER", text: .constant(editingCarrierName), disabled: true)
            } else {
                PixelTextField(label: "TRACKING NO.", text: $newTrackingNumber)
                carrierPicker
            }
            PixelTextField(label: "ITEM NAME", text: $newItemName)
            PixelTextField(label: "MEMO", text: $newMemo)

            PixelButton(title: submitButtonTitle) {
                submit()
            }
            .disabled(!isFormValid || isSubmitting)
            .opacity((!isFormValid || isSubmitting) ? 0.5 : 1.0)
        }
        .padding(14)
        .pixelBox(border: Color.pixelBorder, bg: Color.pixelSurface, lineWidth: 1.5, notch: 4)
    }

    /// 편집 모드에서 읽기전용으로 보여줄 택배사 이름
    private var editingCarrierName: String {
        service.carriers.first(where: { $0.id == newCarrierId })?.name ?? newCarrierId
    }

    private var submitButtonTitle: String {
        if isEditing { return isSubmitting ? "EDITING..." : "EDIT" }
        return isSubmitting ? "ADDING..." : "ADD"
    }

    private var carrierPicker: some View {
        PixelDropdown(
            label: "CARRIER",
            options: service.carriers.map { PixelDropdownOption(id: $0.id, name: $0.name) },
            selectedId: $newCarrierId
        )
    }

    private var isFormValid: Bool {
        !newCarrierId.isEmpty && !newTrackingNumber.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - Actions

    private func submit(force: Bool = false) {
        if isEditing { submitEdit(); return }

        isSubmitting = true
        Task {
            let name = newItemName.trimmingCharacters(in: .whitespaces)
            let memo = newMemo.trimmingCharacters(in: .whitespaces)
            let result = await service.addTracking(
                carrierId: newCarrierId,
                trackingNumber: newTrackingNumber.trimmingCharacters(in: .whitespaces),
                itemName: name.isEmpty ? nil : name,
                memo: memo.isEmpty ? nil : memo,
                limit: subscription.liveActivityLimit,
                force: force
            )
            isSubmitting = false
            switch result {
            case .success(let id):
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    showAddForm = false
                }
                resetForm()
                highlightNewRow(id: id)        // 새 행 한 번 바운스
                maybeShowFirstAddPaywall()
            case .notFound(let message):
                // 조회 불가 — 확인 다이얼로그를 띄우고, 확인 시 force 로 재시도
                notFoundMessage = message
                showNotFoundConfirm = true
            case .failure:
                break  // service.error 로 오류 알림이 표시됨
            }
        }
    }

    /// 편집 저장 — 품명/메모만 수정
    private func submitEdit() {
        guard let id = editingTrackingId else { return }
        isSubmitting = true
        Task {
            let name = newItemName.trimmingCharacters(in: .whitespaces)
            let memo = newMemo.trimmingCharacters(in: .whitespaces)
            let ok = await service.updateTracking(
                id: id,
                itemName: name.isEmpty ? nil : name,
                memo: memo.isEmpty ? nil : memo
            )
            isSubmitting = false
            if ok {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    showAddForm = false
                }
                resetForm()
            }
            // 실패 시 service.error 로 알림 표시, 폼 유지
        }
    }

    /// 방금 추가된 행을 잠깐 강조(바운스)한 뒤 해제
    private func highlightNewRow(id: Int) {
        justAddedId = id
        Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            if justAddedId == id { justAddedId = nil }
        }
    }

    /// 행의 EDIT 탭 → 폼을 편집 모드로 열고 기존 값으로 채운다
    private func startEditing(_ tracking: TrackingListItem) {
        openRowId = nil
        editingTrackingId = tracking.id
        newTrackingNumber = tracking.trackingNumber
        newCarrierId = tracking.carrierId
        newItemName = tracking.itemName
        newMemo = tracking.memo ?? ""
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            showAddForm = true
        }
    }

    /// 첫 택배 추가 직후 한 번만 업셀 페이월을 띄운다(비구독자 한정).
    private func maybeShowFirstAddPaywall() {
        guard !hasShownFirstAddPaywall, !subscription.isSubscribed else { return }
        hasShownFirstAddPaywall = true
        showFirstAddPaywall = true
    }

    private func resetForm() {
        newTrackingNumber = ""
        newCarrierId = ""
        newItemName = ""
        newMemo = ""
        editingTrackingId = nil
    }

    /// 삭제 확인 다이얼로그 문구 (대상 품명 포함)
    private var deleteConfirmMessage: String {
        let name = pendingDeleteTracking?.itemName ?? ""
        let label = name.isEmpty ? "이 택배" : "'\(name)'"
        return "\(label)를 삭제할까요?\n삭제하면 되돌릴 수 없어요."
    }

    /// 행의 삭제 탭 → 확인 다이얼로그 표시
    private func requestDelete(_ tracking: TrackingListItem) {
        pendingDeleteTracking = tracking
        showDeleteConfirm = true
    }

    /// 확인 후 실제 삭제
    private func performDelete() {
        guard let tracking = pendingDeleteTracking else { return }
        pendingDeleteTracking = nil
        #if DEBUG
        if showDummyData { return }  // 더미 표시 중에는 실제 삭제하지 않음
        #endif
        Task { await service.deleteTracking(id: tracking.id) }
    }

    private func toggleLiveActivity(for tracking: TrackingListItem) {
        Task {
            if service.isInLiveActivity(trackingNumber: tracking.trackingNumber) {
                await service.removeFromLiveActivity(trackingNumber: tracking.trackingNumber)
            } else {
                let limit = subscription.liveActivityLimit
                if service.liveTrackingNumbers.count >= limit {
                    showSubscriptionAlert = true
                } else {
                    await service.addToLiveActivity(trackingNumber: tracking.trackingNumber)
                }
            }
        }
    }
}


#Preview {
    let service = TrackingService(preview: [
        TrackingListItem(
            id: 1,
            carrierId: "cj",
            trackingNumber: "123456789012",
            itemName: "맥북 프로 14인치",
            currentStatus: .delivering,
            currentTValue: 0.8,
            carrierName: "CJ대한통운",
            estimatedDelivery: "오늘",
            createdAt: "2026-04-10T09:00:00Z",
            deliveredAt: nil
        ),
        TrackingListItem(
            id: 2,
            carrierId: "hanjin",
            trackingNumber: "987654321098",
            itemName: "에어팟 프로",
            currentStatus: .inTransitOut,
            currentTValue: 0.5,
            carrierName: "한진택배",
            estimatedDelivery: "내일",
            createdAt: "2026-04-09T15:30:00Z",
            deliveredAt: nil
        ),
        TrackingListItem(
            id: 3,
            carrierId: "lotte",
            trackingNumber: "555444333222",
            itemName: "Nike 에어맥스",
            currentStatus: .delivered,
            currentTValue: 0.95,
            carrierName: "롯데택배",
            estimatedDelivery: nil,
            createdAt: "2026-04-07T11:00:00Z",
            deliveredAt: "2026-04-11T14:22:00Z"
        ),
        TrackingListItem(
            id: 4,
            carrierId: "post",
            trackingNumber: "111222333444",
            itemName: "무선 키보드",
            currentStatus: .registered,
            currentTValue: 0.05,
            carrierName: "우체국택배",
            estimatedDelivery: "3일 후",
            createdAt: "2026-04-12T08:00:00Z",
            deliveredAt: nil
        ),
    ])
    NavigationStack {
        DeliveryListView()
    }
    .environment(service)
    .environment(SubscriptionManager())
}

#Preview("빈 상태 - 달리는 트럭") {
    NavigationStack {
        DeliveryListView()
    }
    .environment(TrackingService(preview: []))
    .environment(SubscriptionManager())
}
