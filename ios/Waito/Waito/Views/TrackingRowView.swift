import SwiftUI

struct TrackingRowView: View {
    let tracking: TrackingListItem
    let isLiveActive: Bool
    let onToggleLiveActivity: () -> Void
    /// 삭제 요청(상위에서 확인 팝업 후 실제 삭제). 슬라이드는 이미 닫고 호출한다.
    var onDelete: () -> Void = {}
    /// 수정 요청(상위에서 입력 폼을 편집 모드로 연다)
    var onEdit: () -> Void = {}
    /// 현재 액션 버튼이 열린 행의 id (한 번에 하나만 열리도록 공유)
    @Binding var openRowId: Int?
    /// 방금 추가돼 한 번 바운스로 강조할 행 id (이 행과 같으면 바운스)
    var justAddedId: Int? = nil

    @State private var isExpanded = false
    /// 추가 직후 강조 바운스 스케일
    @State private var bounceScale: CGFloat = 1

    // 왼쪽 슬라이드 → 삭제 버튼 노출
    @State private var offsetX: CGFloat = 0
    private let delWidth: CGFloat = 88
    private let slideGap: CGFloat = 8
    /// 완전히 열렸을 때 행이 왼쪽으로 밀리는 거리 (삭제 버튼 + 간격)
    private var openOffset: CGFloat { -(delWidth + slideGap) }
    // 통통 튀는 스프링 (열림/닫힘 공통)
    private let slideSpring = Animation.spring(response: 0.4, dampingFraction: 0.6)
    
    
    private enum DataState { case ok, checking, notFound }

    /// 조회 데이터 상태. 등록 후 12시간 지나도 데이터가 없으면 notFound(번호 확인 유도)
    private var dataState: DataState {
        if tracking.hasTrackingData { return .ok }
        if let created = parseServerDate(tracking.createdAt),
           Date().timeIntervalSince(created) > 12 * 3600 {
            return .notFound
        }
        return .checking
    }

    /// 프로그레스 색 — 데이터 없으면 회색
    private var progressColor: Color {
        dataState == .ok ? pixelStatusColor(tracking.currentStatus) : Color.pixelBorder
    }

    var mainInfo: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(tracking.itemName.uppercased())
                .font(pixelFont(15))
                .foregroundStyle(dataState == .ok ? Color.pixelText : Color.pixelMuted)
                .lineLimit(1)

            HStack(spacing: 6) {
                Text(formatDate(tracking.createdAt))
                    .font(pixelFont(12))
                    .foregroundStyle(Color.pixelMuted)

                switch dataState {
                case .checking:
                    Text("· 확인 중")
                        .font(pixelFont(10))
                        .foregroundStyle(Color.pixelMuted)
                case .notFound:
                    Text("· 번호 확인 필요")
                        .font(pixelFont(10))
                        .foregroundStyle(Color.pixelOrange)
                case .ok:
                    // 정상 배송: 현재 단계명(간선상차 등)을 같은 자리에 표시 — DI/LA 와 동일한 status.displayName
                    Text("· \(tracking.currentStatus.displayName)")
                        .font(pixelFont(10))
                        .foregroundStyle(progressColor)
                }
            }
        }
    }
    
    var liveActivityBtn: some View {
        PixelToggle(isOn: isLiveActive, onToggle: onToggleLiveActivity)
    }
    
    var horizontalProgress: some View {
        // 접힘(간략)은 어느 택배든 고정 6단계로 과정을 표시(②). 펼치면 실제 이벤트 상태.
        fixedStepBar
            .frame(height: 5)
            .padding(.horizontal, 14)
            .padding(.bottom, 8)
            .transition(.opacity)
    }

    /// 이벤트 개수 기반 가로 점 바 — 모든 점 채움(지나간 이벤트).
    private func eventDotBar(count: Int) -> some View {
        GeometryReader { geo in
            let dotSize: CGFloat = 5
            let gap: CGFloat = 4
            let lineWidth = count > 1
                ? (geo.size.width - (dotSize + gap * 2) * CGFloat(count) + gap * 2) / CGFloat(count - 1)
                : 0
            let activeColor = progressColor

            ZStack(alignment: .leading) {
                if count > 1 {
                    ForEach(0..<count - 1, id: \.self) { i in
                        let x = (dotSize + gap * 2 + lineWidth) * CGFloat(i) + dotSize + gap
                        Rectangle()
                            .fill(activeColor)
                            .frame(width: lineWidth, height: 1)
                            .offset(x: x, y: dotSize / 2 - 0.5)
                    }
                }
                ForEach(0..<count, id: \.self) { i in
                    let x = (dotSize + gap * 2 + lineWidth) * CGFloat(i)
                    Rectangle()
                        .fill(activeColor)
                        .frame(width: dotSize, height: dotSize)
                        .offset(x: x)
                }
            }
        }
    }

    /// 접힘(간략) 진행바 — 어느 택배든 고정 6단계(접수·집화완료·간선상차·배송출발·배송중·배송완료).
    /// 현재 상태 인덱스까지 채움. 펼치면 실제 이벤트 타임라인(②).
    private var fixedStepBar: some View {
        GeometryReader { geo in
            let steps = DeliveryStatus.collapsedStages.count   // 6
            let curIndex = tracking.currentStatus.collapsedStepIndex
            let dotSize: CGFloat = 5
            let gap: CGFloat = 4
            let lineWidth = (geo.size.width - (dotSize + gap * 2) * CGFloat(steps) + gap * 2) / CGFloat(steps - 1)
            let activeColor = progressColor

            ZStack(alignment: .leading) {
                ForEach(0..<steps - 1, id: \.self) { i in
                    let x = (dotSize + gap * 2 + lineWidth) * CGFloat(i) + dotSize + gap
                    Rectangle()
                        .fill(i < curIndex ? activeColor : Color.pixelBorder)
                        .frame(width: lineWidth, height: 1)
                        .offset(x: x, y: dotSize / 2 - 0.5)
                }
                ForEach(0..<steps, id: \.self) { i in
                    let x = (dotSize + gap * 2 + lineWidth) * CGFloat(i)
                    Rectangle()
                        .fill(i <= curIndex ? activeColor : Color.pixelBorder)
                        .frame(width: dotSize, height: dotSize)
                        .offset(x: x)
                }
            }
        }
    }
    
    var verticalProgress: some View {
        Group {
            if let events = tracking.events, !events.isEmpty {
                eventTimeline(events)
            } else {
                statusFallbackTimeline
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
    }

    /// 원본 이벤트 기반 세로 타임라인 — 라벨 = 택배사 description, 모두 지나감(채움), 마지막=현재.
    private func eventTimeline(_ events: [TrackingEvent]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                let isCurrent = index == events.count - 1

                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .top, spacing: 10) {
                        Rectangle()
                            .fill(progressColor)
                            .frame(width: 7, height: 7)
                            .padding(.top, 2)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(event.description)
                                .font(pixelFont(isCurrent ? 12 : 9))
                                .foregroundStyle(isCurrent ? progressColor : Color.pixelText.opacity(0.6))
                                .fixedSize(horizontal: false, vertical: true)

                            if let sub = eventSubLabel(event) {
                                Text(sub)
                                    .font(pixelFont(8))
                                    .foregroundStyle(Color.pixelMuted.opacity(0.7))
                            }
                        }
                    }

                    if index < events.count - 1 {
                        Rectangle()
                            .fill(progressColor)
                            .frame(width: 1, height: 19)
                            .padding(.leading, 3)
                    }
                }
            }
        }
    }

    /// 이벤트 없을 때 폴백 — 기존 status 기반 고정 7단계 세로 타임라인.
    private var statusFallbackTimeline: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(DeliveryStatus.allCases.enumerated()), id: \.element) { index, stage in
                let isCurrent = stage == tracking.currentStatus
                let isPast = stage.order < tracking.currentStatus.order

                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .center, spacing: 10) {
                        Rectangle()
                            .fill((isPast || isCurrent) ? progressColor : Color.pixelBorder)
                            .frame(width: 7, height: 7)

                        Text(stage.displayName)
                            .font(pixelFont(isCurrent ? 12 : 9))
                            .foregroundStyle(
                                isCurrent ? progressColor
                                : isPast   ? Color.pixelText.opacity(0.6)
                                :            Color.pixelMuted.opacity(0.4)
                            )
                    }

                    if index < DeliveryStatus.allCases.count - 1 {
                        Rectangle()
                            .fill(isPast ? progressColor : Color.pixelBorder)
                            .frame(width: 1, height: 19)
                            .padding(.leading, 3)
                    }
                }
            }
        }
    }

    /// 이벤트 보조 라벨 — "시간 · 위치" (둘 다 없으면 nil)
    private func eventSubLabel(_ event: TrackingEvent) -> String? {
        let time = formatDate(event.eventTime)
        let loc = event.location?.trimmingCharacters(in: .whitespaces)
        switch (time.isEmpty, loc?.isEmpty ?? true) {
        case (false, false): return "\(time) · \(loc!)"
        case (false, true):  return time
        case (true, false):  return loc
        case (true, true):   return nil
        }
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
        HStack(spacing: slideGap) {
            // 행 콘텐츠 (컨테이너 전체 너비)
            rowContent
                .frame(maxWidth: .infinity)

            // 삭제/수정 버튼 (행 오른쪽 밖에 대기하다 함께 딸려나옴, 각 절반 높이)
            actionColumn
        }
        // 액션 버튼을 행 오른쪽 바깥으로 밀어내 평소엔 숨김
        .padding(.trailing, openOffset)
        .offset(x: offsetX)
        .scaleEffect(bounceScale)
        .gesture(dragGesture)
        .clipped()
        .onChange(of: openRowId) { _, newValue in
            // 다른 행이 열리면 이 행은 닫는다
            if newValue != tracking.id && offsetX != 0 {
                withAnimation(slideSpring) { offsetX = 0 }
            }
        }
        .onChange(of: justAddedId) { _, newValue in
            if newValue == tracking.id { playAddBounce() }
        }
        .onAppear {
            if justAddedId == tracking.id { playAddBounce() }
        }
    }

    /// 추가 직후 한 번 통통 튀는 강조
    private func playAddBounce() {
        bounceScale = 0.92
        withAnimation(.spring(response: 0.45, dampingFraction: 0.45)) {
            bounceScale = 1
        }
    }

    private var rowContent: some View {
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

                    if let memo = tracking.memo, !memo.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("MEMO")
                                .font(pixelFont(8))
                                .foregroundStyle(Color.pixelMuted)
                            Text(memo)
                                .font(pixelFont(10))
                                .foregroundStyle(Color.pixelText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 10)
                    }
                }
                .transition(.opacity)
            }

            detailBtn
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if offsetX != 0 {
                // 슬라이드가 열려 있으면 탭은 닫기
                withAnimation(slideSpring) { offsetX = 0 }
                if openRowId == tracking.id { openRowId = nil }
            } else {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { isExpanded.toggle() }
            }
        }
        .clipped()
        .pixelBox(border: Color.pixelBorder, bg: Color.pixelSurface, lineWidth: 1.5, notch: 4)
    }

    // MARK: - 액션 버튼 (삭제 / 수정, 각 절반 높이)

    private var actionColumn: some View {
        VStack(spacing: slideGap) {
            deleteButton
            editButton
        }
        .frame(width: delWidth)
        .frame(maxHeight: .infinity)
    }

    private var deleteButton: some View {
        Button {
            withAnimation(slideSpring) { offsetX = 0 }
            if openRowId == tracking.id { openRowId = nil }
            onDelete()        // 상위에서 확인 팝업 후 실제 삭제
        } label: {
            HStack(spacing: 6) {
                Text(">")
                Text("DEL_")
            }
            .font(pixelFont(11))
            .foregroundStyle(Color.pixelText)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .pixelBox(border: Color.pixelRed.opacity(0.7), bg: Color.pixelRed, lineWidth: 1.5, notch: 4)
        }
        .buttonStyle(.plain)
    }

    private var editButton: some View {
        Button {
            withAnimation(slideSpring) { offsetX = 0 }
            if openRowId == tracking.id { openRowId = nil }
            onEdit()
        } label: {
            HStack(spacing: 6) {
                Text(">")
                Text("EDIT_")
            }
            .font(pixelFont(11))
            .foregroundStyle(Color.pixelText)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .pixelBox(border: Color.pixelBorder, bg: Color.pixelSurface, lineWidth: 1.5, notch: 4)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 슬라이드 제스처

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { value in
                let t = value.translation.width
                if t < 0 {
                    // 왼쪽으로 끌기 시작하면 이 행을 활성화 → 다른 행은 닫힘
                    if openRowId != tracking.id { openRowId = tracking.id }
                    if t >= openOffset {
                        offsetX = t                                  // 정상 범위: 손가락 따라감
                    } else {
                        // 최대치를 넘기면 고무줄처럼 저항 (탄력)
                        offsetX = openOffset + (t - openOffset) * 0.25
                    }
                } else if offsetX < 0 {
                    offsetX = min(0, openOffset + t)                 // 열린 상태에서 오른쪽으로 끌면 닫힘
                }
            }
            .onEnded { value in
                // 던지는 속도까지 반영해 열림/닫힘 결정 후 스프링으로 안착
                let predicted = value.predictedEndTranslation.width
                let willOpen = predicted < openOffset / 2
                withAnimation(slideSpring) {
                    offsetX = willOpen ? openOffset : 0
                }
                if willOpen {
                    openRowId = tracking.id
                } else if openRowId == tracking.id {
                    openRowId = nil
                }
            }
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

    /// 서버(SQLite datetime "yyyy-MM-dd HH:mm:ss", UTC) 또는 ISO8601 문자열을 Date 로 파싱
    private func parseServerDate(_ s: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: s) { return d }
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: s) { return d }

        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(identifier: "UTC")
        df.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return df.date(from: s)
    }

    private func formatDate(_ isoString: String) -> String {
        guard let date = parseServerDate(isoString) else { return isoString }
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
        TrackingRowView(tracking: item, isLiveActive: true, onToggleLiveActivity: {}, openRowId: .constant(nil))
        TrackingRowView(tracking: item, isLiveActive: false, onToggleLiveActivity: {}, openRowId: .constant(nil))
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
        TrackingRowView(tracking: item, isLiveActive: false, onToggleLiveActivity: {}, openRowId: .constant(nil))
    }
    .listStyle(.plain)
    .scrollContentBackground(.hidden)
    .background(Color.bg)
}
