import SwiftUI

// MARK: - 택배 목록

struct DeliveryListView: View {
    @Environment(TrackingService.self) private var service

    @State private var showAddSheet = false
    @State private var selectedTrackingId: Int?
    @State private var showError = false

    var body: some View {
        Group {
            if service.trackings.isEmpty && !service.isLoading {
                ContentUnavailableView(
                    "등록된 택배가 없어요",
                    systemImage: "box.truck",
                    description: Text("+ 버튼을 눌러 운송장을 등록해보세요")
                )
            } else {
                List {
                    ForEach(service.trackings) { tracking in
                        Button {
                            selectedTrackingId = tracking.id
                        } label: {
                            TrackingRowView(tracking: tracking)
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete(perform: deleteTracking)
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("내 택배")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .refreshable {
            await service.loadTrackings()
        }
        .sheet(isPresented: $showAddSheet) {
            AddTrackingView()
        }
        .navigationDestination(item: $selectedTrackingId) { trackingId in
            TrackingDetailView(trackingId: trackingId)
        }
        .onChange(of: service.error) { _, newValue in
            showError = newValue != nil
        }
        .alert("오류", isPresented: $showError) {
            Button("확인", role: .cancel) {
                service.clearError()
            }
        } message: {
            Text(service.error ?? "")
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

// MARK: - 택배 행

struct TrackingRowView: View {
    let tracking: TrackingListItem

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(tracking.itemName)
                    .font(.body)
                    .fontWeight(.medium)

                HStack(spacing: 4) {
                    Text(tracking.carrierName)
                    Text(tracking.trackingNumber)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                // 상태 배지
                Text(tracking.currentStatus.displayName)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(statusColor(tracking.currentStatus))
                    .clipShape(Capsule())

                // 미니 프로그레스
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(Color(.systemGray5))

                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(statusColor(tracking.currentStatus))
                            .frame(width: geo.size.width * tracking.currentStatus.progress)
                    }
                }
                .frame(width: 60, height: 3)
            }
        }
        .padding(.vertical, 4)
    }

    private func statusColor(_ status: DeliveryStatus) -> Color {
        if status.isCompleted { return .green }
        if status.isActive { return .blue }
        return .orange
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
    NavigationStack {
        DeliveryListView()
    }
    .environment(TrackingService())
}
