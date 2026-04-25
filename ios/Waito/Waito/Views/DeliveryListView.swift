import SwiftUI

// MARK: - 택배 목록

struct DeliveryListView: View {
    @Environment(TrackingService.self) private var service
    @Environment(SubscriptionManager.self) private var subscription

    @State private var showAddForm = false
    @State private var showError = false
    @State private var showSubscriptionAlert = false

    // 입력 폼 상태
    @State private var newTrackingNumber = ""
    @State private var newCarrierId = ""
    @State private var newItemName = ""
    @State private var newMemo = ""
    @State private var isSubmitting = false

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
            )
            .task {
                if service.carriers.isEmpty {
                    await service.loadCarriers()
                }
            }
    }

    private var listContent: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                actionButtons

                if showAddForm {
                    inlineAddForm
                        .transition(.opacity)
                }

                ForEach(service.trackings) { tracking in
                    TrackingRowView(
                        tracking: tracking,
                        isLiveActive: service.isInLiveActivity(trackingNumber: tracking.trackingNumber),
                        onToggleLiveActivity: { toggleLiveActivity(for: tracking) }
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
        .background(Color.bg)
        .refreshable { await service.loadTrackings() }
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
        NavigationLink(destination: TruckCustomizeView()) {
            HStack(spacing: 6) {
                Text("🚚")
                    .font(.system(size: 16))
                if wide {
                    Text("MY TRUCK_")
                        .font(pixelFont(10))
                        .foregroundStyle(Color.pixelText)
                }
            }
            .frame(maxWidth: wide ? .infinity : nil)
            .frame(width: wide ? nil : 46, height: 46)
            .padding(.horizontal, wide ? 0 : 0)
            .pixelBox(border: Color.pixelOrange.opacity(0.5), bg: Color.pixelOrange.opacity(0.08), lineWidth: 1.5, notch: 4)
        }
        .buttonStyle(.plain)
    }

    private var addButton: some View {
        Button {
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

    private var inlineAddForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            PixelTextField(label: "TRACKING NO.", text: $newTrackingNumber)
            carrierPicker
            PixelTextField(label: "ITEM NAME", text: $newItemName)
            PixelTextField(label: "MEMO", text: $newMemo)

            PixelButton(title: isSubmitting ? "ADDING..." : "ADD") {
                submit()
            }
            .disabled(!isFormValid || isSubmitting)
            .opacity((!isFormValid || isSubmitting) ? 0.5 : 1.0)
        }
        .padding(14)
        .pixelBox(border: Color.pixelBorder, bg: Color.pixelSurface, lineWidth: 1.5, notch: 4)
    }

    private var carrierPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CARRIER")
                .font(pixelFont(9))
                .foregroundStyle(Color.pixelOrange)

            Menu {
                ForEach(service.carriers) { carrier in
                    Button(carrier.name) { newCarrierId = carrier.id }
                }
                if service.carriers.isEmpty {
                    Button("로딩 중...") {}
                        .disabled(true)
                }
            } label: {
                HStack {
                    Text(selectedCarrierName)
                        .font(pixelFont(10))
                        .foregroundStyle(newCarrierId.isEmpty ? Color.pixelMuted : Color.pixelText)
                    Spacer()
                    Text("▼")
                        .font(pixelFont(8))
                        .foregroundStyle(Color.pixelMuted)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 14)
                .pixelBox()
            }
        }
    }

    private var selectedCarrierName: String {
        service.carriers.first(where: { $0.id == newCarrierId })?.name ?? "선택해주세요"
    }

    private var isFormValid: Bool {
        !newCarrierId.isEmpty && !newTrackingNumber.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - Actions

    private func submit() {
        isSubmitting = true
        Task {
            let name = newItemName.trimmingCharacters(in: .whitespaces)
            let success = await service.addTracking(
                carrierId: newCarrierId,
                trackingNumber: newTrackingNumber.trimmingCharacters(in: .whitespaces),
                itemName: name.isEmpty ? nil : name,
                limit: subscription.liveActivityLimit
            )
            isSubmitting = false
            if success {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    showAddForm = false
                }
                resetForm()
            }
        }
    }

    private func resetForm() {
        newTrackingNumber = ""
        newCarrierId = ""
        newItemName = ""
        newMemo = ""
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
