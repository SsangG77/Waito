import SwiftUI

struct TrackingRowView: View {
    let tracking: TrackingListItem
    let isLiveActive: Bool
    let onToggleLiveActivity: () -> Void

    @State private var isExpanded = false
    
    
    var mainInfo: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(tracking.itemName.uppercased())
                .font(pixelFont(15))
                .foregroundStyle(Color.pixelText)
                .lineLimit(1)

            Text(formatDate(tracking.createdAt))
                .font(pixelFont(12))
                .foregroundStyle(Color.pixelMuted)
        }
    }
    
    var liveActivityBtn: some View {
        Button { onToggleLiveActivity() } label: {
            Image(systemName: isLiveActive
                  ? "antenna.radiowaves.left.and.right"
                  : "antenna.radiowaves.left.and.right.slash")
                .font(.system(size: 11))
                .foregroundStyle(isLiveActive ? Color.pixelOrange : Color.pixelMuted)
                .frame(width: 26, height: 26)
                .overlay(Rectangle().stroke(Color.pixelBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
    
    var horizontalProgress: some View {
        GeometryReader { geo in
            let steps = 7
            let dotSize: CGFloat = 5
            let gap: CGFloat = 4
            let lineWidth = (geo.size.width - (dotSize + gap * 2) * CGFloat(steps) + gap * 2) / CGFloat(steps - 1)
            let activeColor = pixelStatusColor(tracking.currentStatus)

            ZStack(alignment: .leading) {
                ForEach(0..<steps - 1) { i in
                    let x = (dotSize + gap * 2 + lineWidth) * CGFloat(i) + dotSize + gap
                    let filled = tracking.currentStatus.isCompleted || CGFloat(i + 1) / CGFloat(steps) <= tracking.currentStatus.progress
                    
                    Rectangle()
                        .fill(filled ? activeColor : Color.pixelBorder)
                        .frame(width: lineWidth, height: 1)
                        .offset(x: x, y: dotSize / 2 - 0.5)
                }
                ForEach(0..<steps) { i in
                    let x = (dotSize + gap * 2 + lineWidth) * CGFloat(i)
                    let filled = tracking.currentStatus.isCompleted || CGFloat(i) / CGFloat(steps) < tracking.currentStatus.progress
                    
                    Rectangle()
                        .fill(filled ? activeColor : Color.pixelBorder)
                        .frame(width: dotSize, height: dotSize)
                        .offset(x: x)
                }
            }
        }
        .frame(height: 5)
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
        .transition(.opacity)
    }
    
    var verticalProgress: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(DeliveryStatus.allCases.enumerated()), id: \.element) { index, stage in
                let isCurrent = stage == tracking.currentStatus
                let isPast = stage.order < tracking.currentStatus.order

                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .center, spacing: 10) {
                        Rectangle()
                            .fill((isPast || isCurrent) ? pixelStatusColor(tracking.currentStatus) : Color.pixelBorder)
                            .frame(width: 7, height: 7)

                        Text(stage.displayName)
                            .font(pixelFont(isCurrent ? 12 : 9))
                            .foregroundStyle(
                                isCurrent ? pixelStatusColor(tracking.currentStatus)
                                : isPast   ? Color.pixelText.opacity(0.6)
                                :            Color.pixelMuted.opacity(0.4)
                            )
                    }

                    if index < DeliveryStatus.allCases.count - 1 {
                        Rectangle()
                            .fill(isPast ? pixelStatusColor(tracking.currentStatus) : Color.pixelBorder)
                            .frame(width: 1, height: 19)
                            .padding(.leading, 3)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
    }
    
    var detailBtn: some View {
        HStack {
            Spacer()
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Text(isExpanded ? "CLOSE" : "DETAIL")
                        .font(pixelFont(10))
                        .foregroundStyle(Color.pixelMuted)
                    PixelChevron(isExpanded: isExpanded)
                        .frame(width: 10, height: 7)
                        .foregroundStyle(Color.pixelMuted)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // MARK: 기본 영역 (항상 보임)
            HStack(alignment: .top, spacing: 12) {
                mainInfo

                Spacer()

                if !tracking.currentStatus.isCompleted {
                    liveActivityBtn
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            // 접힌 상태: 가로 픽셀 프로그레스 바
            if !isExpanded {
                horizontalProgress
                    .transition(.opacity)
            }

            // 펼친 상태: 세로 타임라인
            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    Rectangle()
                        .fill(Color.pixelBorder)
                        .frame(height: 1)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 10)

                    verticalProgress
                }
                .transition(.opacity)
            }

            detailBtn
        }
        .clipped()
        .pixelBox(border: Color.pixelBorder, bg: Color.pixelSurface, lineWidth: 1.5, notch: 4)
        .listRowBackground(Color.bg)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
    }

    private func labelValue(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(pixelFont(6))
                .foregroundStyle(Color.pixelMuted)
            Text(value)
                .font(pixelFont(8))
                .foregroundStyle(Color.pixelOrange)
        }
    }

    private func pixelStatusColor(_ status: DeliveryStatus) -> Color {
        switch status {
        case .delivered:  return Color(hex: "#22C55E")
        case .registered: return Color.pixelMuted
        default:          return Color.pixelOrange
        }
    }

    private func formatDate(_ isoString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: isoString) ?? ISO8601DateFormatter().date(from: isoString) else {
            return isoString
        }
        let display = DateFormatter()
        display.locale = Locale(identifier: "ko_KR")
        display.dateFormat = "yyyy.MM.dd"
        return display.string(from: date)
    }
}

// MARK: - 픽셀 Chevron Shape

struct PixelChevron: Shape {
    var isExpanded: Bool

    func path(in rect: CGRect) -> Path {
        var p = Path()
        if isExpanded {
            // ▲ 위쪽 화살표
            p.move(to:    CGPoint(x: rect.midX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            p.closeSubpath()
        } else {
            // ▼ 아래쪽 화살표
            p.move(to:    CGPoint(x: rect.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            p.closeSubpath()
        }
        return p
    }
}

// MARK: - Preview

#Preview("배송중") {
    let item = TrackingListItem(
        id: 1,
        carrierId: "cj",
        trackingNumber: "123456789012",
        itemName: "맥북 프로 14인치",
        currentStatus: .delivering,
        currentTValue: 0.8,
        carrierName: "CJ대한통운",
        estimatedDelivery: "오늘",
        createdAt: "2026-04-01T00:00:00Z",
        deliveredAt: nil
    )
    List {
        TrackingRowView(tracking: item, isLiveActive: true, onToggleLiveActivity: {})
        TrackingRowView(tracking: item, isLiveActive: false, onToggleLiveActivity: {})
    }
    .listStyle(.plain)
    .scrollContentBackground(.hidden)
    .background(Color.bg)
}

#Preview("배송완료") {
    let item = TrackingListItem(
        id: 2,
        carrierId: "hanjin",
        trackingNumber: "987654321098",
        itemName: "에어팟 프로",
        currentStatus: .delivered,
        currentTValue: 0.95,
        carrierName: "한진택배",
        estimatedDelivery: nil,
        createdAt: "2026-04-01T00:00:00Z",
        deliveredAt: "2026-04-10T14:30:00Z"
    )
    List {
        TrackingRowView(tracking: item, isLiveActive: false, onToggleLiveActivity: {})
    }
    .listStyle(.plain)
    .scrollContentBackground(.hidden)
    .background(Color.bg)
}
