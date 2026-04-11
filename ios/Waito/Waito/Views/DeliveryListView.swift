import SwiftUI

// MARK: - 택배 목록

struct DeliveryListView: View {
    @Environment(TrackingService.self) private var service
    @Environment(SubscriptionManager.self) private var subscription

    @State private var showAddSheet = false
    @State private var showError = false
    @State private var showSubscriptionAlert = false

    var body: some View {
        listContent
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAddSheet = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAddSheet) { AddTrackingView() }
            .onChange(of: service.error) { _, newValue in showError = newValue != nil }
            .alert("오류", isPresented: $showError) {
                Button("확인", role: .cancel) { service.clearError() }
            } message: {
                Text(service.error ?? "")
            }
            .alert("Waito Plus", isPresented: $showSubscriptionAlert) {
                Button("확인", role: .cancel) {}
            } message: {
                Text("무료 사용자는 Live Activity를 1개까지 등록할 수 있어요.\nWaito Plus 구독 시 2개까지 가능합니다.")
            }
    }

    @ViewBuilder
    private var listContent: some View {
        if service.trackings.isEmpty && !service.isLoading {
            ContentUnavailableView(
                "등록된 택배가 없어요",
                systemImage: "box.truck",
                description: Text("+ 버튼을 눌러 운송장을 등록해보세요")
            )
        } else {
            ScrollView {
                LazyVStack(spacing: 8) {
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

    private func deleteTracking(at offsets: IndexSet) {
        for index in offsets {
            let tracking = service.trackings[index]
            Task {
                await service.deleteTracking(id: tracking.id)
            }
        }
    }
}

// MARK: - 택배 상세

struct TrackingDetailView: View {
    @Environment(TrackingService.self) private var service

    let trackingId: Int
    @State private var detail: TrackingDetail?
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
            } else if let detail {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // 배송 정보
                        infoSection(detail)

                        // 배송 이력 타임라인
                        eventsSection(detail.events)
                    }
                    .padding()
                }
            } else {
                ContentUnavailableView("정보를 불러올 수 없어요", systemImage: "exclamationmark.triangle")
            }
        }
        .navigationTitle(detail?.itemName ?? "상세")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
        .task {
            await refresh()
        }
    }

    private func refresh() async {
        isLoading = detail == nil
        detail = await service.getTrackingDetail(id: trackingId)
        isLoading = false
    }

    // MARK: - 배송 정보 섹션

    private func infoSection(_ detail: TrackingDetail) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("배송 정보")
                .font(.headline)

            GroupBox {
                VStack(spacing: 10) {
                    infoRow("택배사", detail.carrierName)
                    infoRow("운송장", detail.trackingNumber)
                    infoRow("상태", detail.currentStatus.displayName)
                    if let eta = detail.estimatedDelivery {
                        infoRow("도착 예정", eta)
                    }
                }
            }

            // 프로그레스 바
            VStack(spacing: 4) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color(.systemGray5))
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.blue)
                            .frame(width: geo.size.width * detail.currentStatus.progress)
                    }
                }
                .frame(height: 6)

                HStack {
                    Text("접수")
                    Spacer()
                    Text("배송완료")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline)
        }
    }

    // MARK: - 배송 이력 타임라인

    private func eventsSection(_ events: [TrackingEvent]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("배송 이력")
                .font(.headline)

            if events.isEmpty {
                Text("아직 이력이 없어요")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                        HStack(alignment: .top, spacing: 12) {
                            // 타임라인 도트
                            VStack(spacing: 0) {
                                Circle()
                                    .fill(index == 0 ? Color.blue : Color(.systemGray4))
                                    .frame(width: 10, height: 10)

                                if index < events.count - 1 {
                                    Rectangle()
                                        .fill(Color(.systemGray4))
                                        .frame(width: 1.5)
                                        .frame(minHeight: 30)
                                }
                            }

                            // 이벤트 내용
                            VStack(alignment: .leading, spacing: 2) {
                                Text(event.description)
                                    .font(.subheadline)
                                    .fontWeight(index == 0 ? .semibold : .regular)

                                HStack(spacing: 4) {
                                    Text(formatEventTime(event.eventTime))
                                    if let location = event.location {
                                        Text("·")
                                        Text(location)
                                    }
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }

                            Spacer()
                        }
                        .padding(.bottom, index < events.count - 1 ? 8 : 0)
                    }
                }
            }
        }
    }

    private func formatEventTime(_ isoString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: isoString) ?? ISO8601DateFormatter().date(from: isoString) else {
            return isoString
        }
        let display = DateFormatter()
        display.locale = Locale(identifier: "ko_KR")
        display.dateFormat = "M/d HH:mm"
        return display.string(from: date)
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
