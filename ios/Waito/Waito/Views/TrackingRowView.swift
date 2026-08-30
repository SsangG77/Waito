import SwiftUI
import Translation   // 해외 배송 이벤트 원문(영문·중문 등) 온디바이스 번역

/// 펼친 타임라인 노드들의 텍스트 높이를 모아 최댓값을 구한다(세로선 길이 통일용).
private struct NodeTextHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

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
    /// LA 표시 순위 — 1 = 접힌 DI 대표(+잠금화면), 2 = 잠금화면만. 미표시면 nil.
    var liveActivityRank: Int? = nil
    /// ② 뱃지 탭 → 이 택배를 DI 대표(①)로 승격
    var onPromoteToPrimary: () -> Void = {}

    @State private var isExpanded = false
    // 해외 이벤트 번역 (온디바이스 Translation framework)
    @State private var showTranslated = false
    @State private var translatedById: [Int: String] = [:]
    @State private var translationConfig: TranslationSession.Configuration?
    /// 추가 직후 강조 바운스 스케일
    @State private var bounceScale: CGFloat = 1
    /// 펼친 타임라인에서 가장 긴 노드의 텍스트 높이 — 모든 노드를 이 높이로 맞춰 세로선 길이를 통일
    @State private var maxNodeTextHeight: CGFloat = 0
    /// 추가 직후 슬라이드 힌트를 이미 재생했는지 (스크롤 재등장 시 반복 방지)
    @State private var didPlayAddHint = false
    /// 슬라이드 힌트는 앱 생애 최초 1회(첫 택배)만 — 두 번째 추가는 페이월이 뜨므로 겹치지 않게.
    @AppStorage("has_shown_slide_hint") private var hasShownSlideHint = false

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
                .font(pixelFont(17))
                .foregroundStyle(dataState == .ok ? Color.pixelText : Color.pixelMuted)
                .lineLimit(1)

            HStack(spacing: 6) {
                Text(formatDate(tracking.createdAt))
                    .font(pixelFont(13))
                    .foregroundStyle(Color.pixelMuted)

                switch dataState {
                case .checking:
                    Text("· 확인 중")
                        .font(pixelFont(13))
                        .foregroundStyle(Color.pixelMuted)
                case .notFound:
                    Text("· 번호 확인 필요")
                        .font(pixelFont(13))
                        .foregroundStyle(Color.pixelOrange)
                case .ok:
                    // 정상 배송: 현재 단계명(간선상차·통관 등)을 같은 자리에 표시 — DI/LA 와 동일한 stageInfo
                    Text("· \(tracking.stageInfo.currentName)")
                        .font(pixelFont(13))
                        .foregroundStyle(progressColor)
                }
            }
        }
    }
    
    var liveActivityBtn: some View {
        VStack(alignment: .trailing, spacing: 5) {
            PixelToggle(isOn: isLiveActive, onToggle: onToggleLiveActivity)

            // 어디에 표시되는지 명시(피드백: "2개 기준 불명확") — ①=DI 대표, ②=잠금화면만.
            // ② 탭 시 ①로 승격해 순서도 사용자가 제어.
            if isLiveActive, let rank = liveActivityRank {
                rankBadge(rank)
            }
        }
    }

    /// LA 표시 위치 뱃지 — ① DI·잠금 / ② 잠금(탭=승격)
    private func rankBadge(_ rank: Int) -> some View {
        let isPrimary = rank == 1
        return Button {
            if !isPrimary { onPromoteToPrimary() }
        } label: {
            Text(isPrimary ? "① DI·잠금" : "② 잠금")
                .font(pixelFont(7))
                .foregroundStyle(isPrimary ? Color.pixelOrange : Color.pixelMuted)
                .padding(.horizontal, 5)
                .padding(.vertical, 3)
                .overlay(
                    Rectangle()
                        .stroke(isPrimary ? Color.pixelOrange.opacity(0.5) : Color.pixelBorder, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(isPrimary)
        .accessibilityIdentifier("row_la_rank_badge")
    }
    
    var horizontalProgress: some View {
        // 접힘(간략)은 어느 택배든 고정 단계로 과정을 표시(②). 현재 노드 = 커스텀 트럭.
        fixedStepBar
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

    /// 접힘(간략) 진행바 — 어느 택배든 고정 5단계(접수·집화완료·간선·배송출발·배송완료).
    /// 현재 단계 노드는 네모점 대신 유저 커스텀 트럭 — 위젯(DI 펼침·잠금화면)과 동일 디자인.
    private var fixedStepBar: some View {
        let dotSize: CGFloat = 5
        let gap: CGFloat = 4
        let truckSize: CGFloat = 26
        let cfg = TruckConfigStore.shared.config

        return GeometryReader { geo in
            // 표시 단계 — 국내 5단계 / 해외 6단계(통관 포함)
            let stage = tracking.stageInfo
            let steps = stage.count
            let curIndex = stage.currentIndex
            let lineWidth = (geo.size.width - (dotSize + gap * 2) * CGFloat(steps) + gap * 2) / CGFloat(steps - 1)
            let stepW = dotSize + gap * 2 + lineWidth
            let lineY = truckSize / 2   // 라인·점은 세로 중앙 — 트럭 중심이 점 위치와 일치
            let activeColor = progressColor

            // 트럭 실제 위치(가장자리 클램프 반영) 기준으로 인접 라인을 잘라 간격 유지.
            // 간격 = 점-라인 gap 의 1.5배. 클램프로 트럭이 밀려도 라인이 트럭에 붙지 않는다.
            let cx = stepW * CGFloat(curIndex) + dotSize / 2
            let truckX = min(max(cx, truckSize / 2), geo.size.width - truckSize / 2)
            let truckGapH = gap * 1.5

            ZStack(alignment: .topLeading) {
                ForEach(0..<steps - 1, id: \.self) { i in
                    let defaultStart = stepW * CGFloat(i) + dotSize + gap
                    let defaultEnd = defaultStart + lineWidth
                    let start = i == curIndex ? max(defaultStart, truckX + truckSize / 2 + truckGapH) : defaultStart
                    let end = (i + 1) == curIndex ? min(defaultEnd, truckX - truckSize / 2 - truckGapH) : defaultEnd
                    Rectangle()
                        .fill(i < curIndex ? activeColor : Color.pixelBorder)
                        .frame(width: max(0, end - start), height: 1)
                        .offset(x: start, y: lineY - 0.5)
                }
                // 점 — 현재 단계는 트럭이 대신하므로 생략
                ForEach(0..<steps, id: \.self) { i in
                    if i != curIndex {
                        let x = stepW * CGFloat(i)
                        Rectangle()
                            .fill(i < curIndex ? activeColor : Color.pixelBorder)
                            .frame(width: dotSize, height: dotSize)
                            .offset(x: x, y: lineY - dotSize / 2)
                    }
                }
                // 현재 단계 노드 = 커스텀 트럭
                CatalogTruckView(cab: cfg.cab, truckBody: cfg.body, wheels: cfg.wheelType, size: truckSize)
                    .position(x: truckX, y: lineY - 3)   // 라인 위에 살짝 떠 있게
            }
        }
        .frame(height: truckSize)
    }
    
    var verticalProgress: some View {
        Group {
            if let events = tracking.events, !events.isEmpty {
                // 해외 택배 — 원본 이벤트가 영문·중문 등으로 와서 번역 토글 제공(온디바이스, 서버 전송 없음)
                if tracking.isInternational == true {
                    translateToggle(events)
                }
                eventTimeline(events)
            } else {
                statusFallbackTimeline
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
        // 토글 시 config 가 설정되면 시스템이 세션을 열어 일괄 번역 (언어팩 미설치면 다운로드 안내)
        .translationTask(translationConfig) { session in
            let events = tracking.events ?? []
            let requests = events.map {
                TranslationSession.Request(sourceText: $0.description, clientIdentifier: String($0.id))
            }
            guard let responses = try? await session.translations(from: requests) else { return }
            for response in responses {
                if let idText = response.clientIdentifier, let id = Int(idText) {
                    translatedById[id] = response.targetText
                }
            }
        }
    }

    /// 번역 토글 버튼 — 첫 켬에서 번역 세션 시작, 이후엔 캐시 표시/원문 전환만
    private func translateToggle(_ events: [TrackingEvent]) -> some View {
        HStack {
            Spacer()
            Button {
                if showTranslated {
                    showTranslated = false
                } else {
                    showTranslated = true
                    if translatedById.isEmpty {
                        translationConfig = TranslationSession.Configuration(
                            target: Locale.Language(identifier: "ko")
                        )
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "character.bubble")
                        .font(.system(size: 11))
                    Text(showTranslated ? "원문 보기" : "번역")
                        .font(pixelFont(11))
                }
                .foregroundStyle(showTranslated ? Color.pixelOrange : Color.pixelMuted)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("row_translate_toggle")
        }
        .padding(.bottom, 6)
    }

    /// 원본 이벤트 기반 세로 타임라인 — 라벨 = 택배사 description, 모두 지나감(채움), 마지막=현재.
    private func eventTimeline(_ events: [TrackingEvent]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                let isCurrent = index == events.count - 1
                let isLast = index == events.count - 1
                let loc = event.location?.trimmingCharacters(in: .whitespaces)
                let time = formatDate(event.eventTime)

                HStack(alignment: .top, spacing: 10) {
                    // 레일: 점 + 아래로 늘어나 다음 점까지 잇는 세로선(두 노드 사이 중앙)
                    // 마지막(현재) 노드는 네모점 대신 커스텀 트럭 — 접힘 바·위젯과 동일 컨셉
                    VStack(spacing: 0) {
                        if isLast {
                            let cfg = TruckConfigStore.shared.config
                            // 점 슬롯(7×7)은 레이아웃용 자리만 차지, 트럭은 오버레이로 실제 26pt 로 그림.
                            // (CatalogTruckView 는 높이 제안에 눌려 축소되므로 명시 frame 필수)
                            Color.clear
                                .frame(width: 7, height: 7)
                                .overlay(alignment: .leading) {
                                    CatalogTruckView(cab: cfg.cab, truckBody: cfg.body, wheels: cfg.wheelType, size: 26)
                                        .frame(width: 26, height: 20)
                                }
                        } else {
                            Rectangle()
                                .fill(progressColor)
                                .frame(width: 7, height: 7)
                            Rectangle()
                                .fill(progressColor)
                                .frame(width: 1)
                                .frame(minHeight: 20, maxHeight: .infinity)
                                .padding(.top, 4)   // 점-선 간격 = 접힘 가로바 gap(4)과 동일
                                // 다음 노드가 트럭이면 넘친 높이만큼 더 띄워 선이 트럭에 안 붙게
                                .padding(.bottom, index == events.count - 2 ? 8 : 4)
                        }
                    }
                    .frame(width: 7)
                    .padding(.top, 2)

                    // 원본 메시지 → 위치 → 시간, 세로 정렬
                    VStack(alignment: .leading, spacing: 6) {
                        Text(showTranslated ? (translatedById[event.id] ?? event.description) : event.description)
                            .font(pixelFont(isCurrent ? 15 : 14))
                            // 타이틀(택배사 원본 메시지) — 현재 노드는 상태색으로 강조, 지나간 노드는 밝은 회색.
                            .foregroundStyle(isCurrent ? progressColor : Color.pixelText.opacity(0.8))
                            .fixedSize(horizontal: false, vertical: true)

                        // 위치 · 시간은 한 줄에 가로 배치. 상태색 강조는 타이틀만 — 여기는 노드와 무관하게 동일.
                        HStack(spacing: 6) {
                            if let loc, !loc.isEmpty {
                                Text(loc)
                                if !time.isEmpty { Text("|") }
                            }
                            if !time.isEmpty {
                                Text(time)
                            }
                        }
                        .font(pixelFont(13))
                        .foregroundStyle(Color.pixelText.opacity(0.6))
                    }
                    // 노드 높이를 가장 긴 노드에 맞춰 통일 → 사이를 잇는 세로선 길이도 전부 같아진다.
                    // 측정은 .frame 적용 전 내용 크기 기준(피드백 루프 없음). 마지막 노드는 아래에
                    // 선이 없어 통일 대상에서 제외(측정·적용 모두).
                    .background {
                        if !isLast {
                            GeometryReader { geo in
                                Color.clear.preference(key: NodeTextHeightKey.self, value: geo.size.height)
                            }
                        }
                    }
                    .frame(minHeight: isLast ? 0 : maxNodeTextHeight, alignment: .topLeading)
                    .padding(.leading, isLast ? 19 : 0)  // 트럭(26)이 점 슬롯(7)보다 넓은 만큼 밀어 간격 유지
                    .padding(.bottom, isLast ? 0 : 22)   // 노드 간격
                }
            }
        }
        .onPreferenceChange(NodeTextHeightKey.self) { value in
            Task { @MainActor in maxNodeTextHeight = value }
        }
    }

    /// 이벤트 없을 때 폴백 — 고정 단계(국내 5/해외 6) 세로 타임라인.
    private var statusFallbackTimeline: some View {
        let stageInfo = tracking.stageInfo
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(stageInfo.names.enumerated()), id: \.offset) { index, stageName in
                let curIndex = stageInfo.currentIndex
                let isCurrent = index == curIndex
                let isPast = index < curIndex
                let isLast = index == stageInfo.count - 1

                HStack(alignment: .top, spacing: 10) {
                    // 레일: 점 + 두 노드 사이를 잇는 세로선. 현재 노드 = 커스텀 트럭.
                    VStack(spacing: 0) {
                        if isCurrent {
                            let cfg = TruckConfigStore.shared.config
                            // 점 슬롯(7×7)은 레이아웃용 자리만 차지, 트럭은 오버레이로 실제 26pt 로 그림.
                            Color.clear
                                .frame(width: 7, height: 7)
                                .overlay(alignment: .leading) {
                                    CatalogTruckView(cab: cfg.cab, truckBody: cfg.body, wheels: cfg.wheelType, size: 26)
                                        .frame(width: 26, height: 20)
                                }
                        } else {
                            Rectangle()
                                .fill(isPast ? progressColor : Color.pixelBorder)
                                .frame(width: 7, height: 7)
                        }
                        if !isLast {
                            Rectangle()
                                .fill(isPast ? progressColor : Color.pixelBorder)
                                .frame(width: 1)
                                .frame(minHeight: 20, maxHeight: .infinity)
                                // 트럭(현재 노드)이 위/아래에 있으면 넘친 높이만큼 더 띄움
                                .padding(.top, isCurrent ? 10 : 4)
                                .padding(.bottom, index + 1 == curIndex ? 10 : 4)
                        }
                    }
                    .frame(width: 7)

                    Text(stageName)
                        .font(pixelFont(isCurrent ? 14 : 13))
                        .foregroundStyle(
                            isCurrent ? progressColor
                            : isPast   ? Color.pixelText.opacity(0.6)
                            :            Color.pixelMuted.opacity(0.4)
                        )
                        .padding(.leading, isCurrent ? 19 : 0)  // 트럭(26)이 점 슬롯(7)보다 넓은 만큼 밀어 간격 유지
                        .padding(.bottom, isLast ? 0 : 22)   // 노드 간격
                }
            }
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
                        .font(pixelFont(12))
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
        // 상세로 펼친 동안엔 슬라이드 금지 — 세로 타임라인 스크롤/탭과 섞이지 않게
        .gesture(dragGesture, isEnabled: !isExpanded)
        .clipped()
        .onChange(of: openRowId) { _, newValue in
            // 다른 행이 열리면 이 행은 닫는다
            if newValue != tracking.id && offsetX != 0 {
                withAnimation(slideSpring) { offsetX = 0 }
            }
        }
        .onChange(of: justAddedId) { _, newValue in
            if newValue == tracking.id { playAddHintOnce() }
        }
        .onAppear {
            if justAddedId == tracking.id { playAddHintOnce() }
        }
    }

    /// 추가 직후 1회만 힌트 재생 (onChange·onAppear 중복/스크롤 재등장 방지 + 앱 생애 최초 1회)
    private func playAddHintOnce() {
        guard !didPlayAddHint, !hasShownSlideHint else { return }
        didPlayAddHint = true
        hasShownSlideHint = true
        playAddHint()
    }

    /// 추가 직후: 통통 바운스로 인지 → 삭제/편집 버튼을 슬라이드로 잠깐 노출했다 원위치.
    /// 슬라이드 액션(왼쪽으로 밀면 삭제·편집)이 있다는 걸 자연스럽게 알려주는 온보딩 힌트.
    private func playAddHint() {
        bounceScale = 0.92
        withAnimation(.spring(response: 0.45, dampingFraction: 0.45)) {
            bounceScale = 1
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)   // 바운스 뒤 이어서 슬라이드 시작
            withAnimation(.spring(response: 0.5, dampingFraction: 0.72)) {
                offsetX = openOffset                          // 삭제/편집 버튼 노출
            }
            try? await Task.sleep(nanoseconds: 850_000_000)   // 버튼을 눈에 담을 시간
            // 힌트 도중 사용자가 다른 행을 열지 않았을 때만 닫는다(사용자 조작 존중)
            if openRowId != tracking.id {
                withAnimation(slideSpring) { offsetX = 0 }
            }
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
                                .font(pixelFont(11))
                                .foregroundStyle(Color.pixelMuted)
                            Text(memo)
                                .font(pixelFont(12))
                                .foregroundStyle(Color.pixelText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 10)
                    }

                    // 액션 영역 구분선 (상단 구분선과 동일)
                    Rectangle()
                        .fill(Color.pixelBorder)
                        .frame(height: 1)
                        .padding(.horizontal, 14)
                        .padding(.top, 14)
                        .padding(.bottom, 14)

                    // 펼친 동안엔 슬라이드가 막히므로 같은 액션을 가로로 제공
                    HStack(spacing: slideGap) {
                        deleteButton
                        editButton
                    }
                    .frame(height: 34)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
                    .accessibilityIdentifier("row_expanded_actions")
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
            // 편집 폼이 열리므로 펼쳐둔 상세는 접는다
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { isExpanded = false }
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
                .font(pixelFont(10))
                .foregroundStyle(Color.pixelMuted)
            Text(value)
                .font(pixelFont(12))
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
