# Waito - 프로젝트 컨텍스트

## 앱 개요

**앱 이름**: Waito ("기다려"의 뉘앙스 + Wait + -o)
**플랫폼**: iOS (iPhone 14 Pro 이상, Dynamic Island 탑재 기기)
**핵심 컨셉**: 택배 트럭이 Dynamic Island 테두리를 따라 이동하며 배송 상태를 시각적으로 보여주는 앱

---

## 핵심 기술 원리

### Dynamic Island 착시 효과 (Pixel Pals 방식)
- Dynamic Island의 검정 하드웨어 컷아웃 + Live Activity의 검정(#000000) 배경이 시각적으로 합쳐지는 착시를 이용
- 실제로 테두리에 그리는 것이 아님 — Apple 공식 API(ActivityKit) 범위 내에서 구현
- 트럭 아이콘이 검정 배경 위에서 움직이면, 테두리 위를 달리는 것처럼 보임

```
실제 구조:
┌────────────────────────────┐  ← Live Activity Expanded View
│        (검정 배경 #000000)  │
│   ╭━━━━━━━━━━━━━━━━━╮      │
│   ┃  [Dynamic Island] ┃  🚚 │  ← 트럭이 테두리 밖에 있는 것처럼 보임
│   ╰━━━━━━━━━━━━━━━━━╯      │
└────────────────────────────┘
```

---

## 트럭 경로 설계

### Dynamic Island 외곽선을 시계방향 경로로 정의

```
        ④ 상단 직선
    ③╭━━━━━━━━━━━━━━━━━╮⑤
     ┃                 ┃
    ②┃                 ┃⑥
     ┃                 ┃
    ①╰━━━━━━━━━━━━━━━━━╯⑦
        ⑧ 하단 직선
```

### t값 (0.0 ~ 1.0) 정규화
- t = 0.0 : 하단 왼쪽 시작
- t = 0.25 : 왼쪽 상단 꼭짓점
- t = 0.5 : 상단 오른쪽
- t = 0.75 : 오른쪽 하단
- t = 1.0 : 하단 중앙 (배송 완료, 귀환)

### 배송 단계 → t값 매핑

| 배송 단계 | t값 | 트럭 방향 |
|---|---|---|
| 접수 | 0.05 | ↗ |
| 집화 완료 | 0.2 | ↑ |
| 간선 상차 | 0.35 | → |
| 간선 하차 | 0.5 | → |
| 배송 출발 | 0.65 | ↓ |
| 배송 중 | 0.8 | ↓ |
| 배송 완료 | 0.95 | ← (집으로 귀환) |

### 트럭 아이콘 회전각

| 구간 | 회전각 |
|---|---|
| 하단 직선 | 180° |
| 좌측 직선 | 270° |
| 상단 직선 | 0° |
| 우측 직선 | 90° |
| 곡선 구간 | 진입각~탈출각 선형 보간 |

- 곡선 구간에서 ±15° 기울어짐 추가 (귀여움 포인트)

---

## View 레이어 구조

```
Live Activity Expanded View
├── 배경: #000000 (필수 — 착시 효과의 핵심)
├── Layer 1: Dynamic Island 외곽선
│           - 완료 구간: 흰색
│           - 미완료 구간: 회색(opacity 0.3)
├── Layer 2: 트럭 아이콘
│           - t값 기반 x, y 좌표 계산
│           - 이동 방향에 따라 rotation 적용
│           - spring animation으로 이동
└── Layer 3: 보조 텍스트 (선택)
            - "오늘 도착 예정" 등 하단 표시
```

---

## 상태 변경 애니메이션 시퀀스

```
배송 상태 변경 감지
        ↓
① 트럭 현재 위치에서 bounce (제자리 점프)
        ↓
② 경로 따라 다음 t값 위치로 이동 (spring animation)
        ↓
③ 도착 후 살짝 wiggle
        ↓
④ 완료 구간 외곽선 색상 업데이트
```

---

## 프로젝트 구조 (실제)

### iOS (`ios/Waito/Waito/`)
```
├── WaitoApp.swift                      # 진입점
├── ContentView.swift                   # 루트 + 인앱 Dynamic Island 트럭 오버레이 + 토큰 관찰 시작
├── LiveActivity/
│   └── DeliveryAttributes.swift        # ContentState(items + truckConfig), TrackingItemState
├── Views/
│   ├── DeliveryListView.swift          # 택배 목록 + 인라인 추가 폼 + 정렬바 + 액션 버튼
│   ├── TrackingRowView.swift           # 택배 행(가로 진행바/타임라인, 슬라이드 삭제, 확인중 표시)
│   ├── PixelTheme.swift                # 픽셀 공용 컴포넌트(PixelBox/TextField/Button/Toggle/Dropdown/Alert/Confirm)
│   ├── PixelNavBar.swift, SettingsView.swift
│   ├── PaywallView.swift               # StoreKit SubscriptionStoreView(상품 미등록 시 Unavailable)
│   ├── PlusPaywallView.swift           # 커스텀 풀스크린 페이월(트럭 그리드+혜택+CTA), 잠금 항목 탭 시
│   ├── TruckCustomizeView.swift        # 트럭 꾸미기(잠금 탭 → PlusPaywallView)
│   └── TruckDrawing/                    # CatalogTruckView(이미지 기반) 등 트럭 렌더링
├── Models/
│   ├── DeliveryStatus.swift            # 배송 단계 enum(String raw) + t값/회전각
│   ├── TruckConfig.swift, TruckConfigStore.swift
│   ├── PixelTruckCatalog.swift         # cab27/body33/wheel27 enum, rawValue=에셋 imageset명, requiresPlus 화이트리스트
│   └── API/APIModels.swift             # Carrier, TrackingListItem, 요청/응답 DTO
├── Services/
│   ├── TrackingService.swift           # @Observable 상태관리 + Live Activity + push 토큰 관찰
│   ├── APIClient.swift                 # actor, 서버 REST 호출
│   └── SubscriptionManager.swift
└── (WaitoWidgetExtension/)             # Live Activity 위젯 UI

# AddTrackingView 는 제거됨 — 추가는 DeliveryListView 의 인라인 폼에서 처리
```

### 서버 (`server/src/`) — Express + better-sqlite3(SQLite)
```
├── index.ts                            # 앱 부팅(initDb, 폴링/credential 스케줄러)
├── config.ts                           # 환경변수(tracker credential, APNS_*)
├── db/database.ts, migrations/001_initial.sql  # 멱등 컬럼 마이그레이션 포함
├── routes/
│   ├── carriers.ts                     # GET /api/carriers (CARRIERS 상수)
│   ├── trackings.ts                    # 택배 CRUD + push-token 등록 + force 추가
│   ├── devices.ts                      # 디바이스 등록 + push-to-start-token 등록
│   ├── webhooks.ts                     # tracker.delivery 콜백 → track 재조회
│   └── admin.ts                        # credential 관리 HTML 페이지
└── services/
    ├── trackerApi.ts                   # tracker.delivery GraphQL(track/registerWebhook)
    ├── pollingService.ts               # 폴링 + webhook keep-alive 스케줄러
    ├── pushService.ts                  # Live Activity update/end + push-to-start
    ├── apnsClient.ts                   # APNs HTTP/2 + ES256 JWT (Node 내장 crypto/http2)
    ├── statusMapper.ts, credentialMonitor.ts
```

---

## 데이터 모델

### DeliveryStatus enum

```swift
enum DeliveryStatus {
    case registered       // 접수       t = 0.05
    case pickedUp         // 집화완료   t = 0.2
    case inTransitIn      // 간선상차   t = 0.35
    case inTransitOut     // 간선하차   t = 0.5
    case outForDelivery   // 배송출발   t = 0.65
    case delivering       // 배송중     t = 0.8
    case delivered        // 배송완료   t = 0.95

    var progress: CGFloat { /* t값 반환 */ }
    var rotationAngle: Double { /* 회전각 반환 */ }
}
```

### ActivityKit ContentState (실제 구현)

```swift
struct TrackingItemState: Codable, Hashable {
    var trackingNumber: String
    var status: DeliveryStatus
    var carrierName: String
    var itemName: String
    var estimatedDelivery: String?
}

struct DeliveryAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var items: [TrackingItemState]        // 여러 택배(무료 1개 / 유료 2개)
        var truckConfig: TruckConfig = .default  // 사용자가 고른 트럭 외형
    }
    var deviceId: String                      // 디바이스 식별(= device_token)
}
```

> ⚠️ 서버가 보내는 APNs `content-state` 는 이 구조와 **정확히 일치**해야 디코딩됨.
> `TruckConfig` 는 키 누락/잘못된 enum 값에도 견디도록 커스텀 `init(from:)` 으로 폴백 처리.

---

## 데이터 흐름 (실제)

```
서버: tracker.delivery webhook(상태변경 시) 또는 폴링(2h/30m)
        ↓
trackPackage(GraphQL) → 이벤트 파싱 → DeliveryStatus 매핑 → DB 갱신
        ↓
상태 변경 시 pushService.pushTrackingUpdate:
  ├─ Live Activity 살아있음(시작 후 8h 미만) → APNs update (무음 화면 갱신)
  └─ 죽음(8h 경과/미시작) → APNs push-to-start 로 되살림 (알림 동반)
        ↓
iOS: 위젯이 content-state(items+truckConfig) 렌더 → 트럭 표시
```

### Live Activity 푸시 아키텍처 (핵심)
- **APNs 토큰 인증**: `apnsClient.ts` 가 `.p8` 키로 ES256 JWT 서명(Node 내장 crypto) + HTTP/2 전송. 외부 패키지 0.
  - 키/설정 없으면 모든 푸시 graceful skip (앱은 인앱 동작). `.p8` 설정법은 Notion "p8 파일 설정" 참고.
  - sandbox/production 은 `APNS_PRODUCTION` 로 전환. `apns-topic` = `<bundleId>.push-type.liveactivity`.
- **두 종류 토큰**: update 토큰(Activity 인스턴스당, 갱신용) / push-to-start 토큰(디바이스당, 되살리기용, iOS 17.2+).
  - 앱이 `Activity.pushToStartTokenUpdates` 관찰 → `truckConfig` 와 함께 서버에 등록(devices 테이블).
- **8시간 한도 대응**: Live Activity 는 8h 후 시스템이 종료. 별도 타이머 없이 **상태 변경 시점에** 죽었으면 push-to-start 로 되살리는 이벤트 기반.
- **알림 정책**: 중간 상태 update = 무음 / 배송 완료(end) = 배너 + 1h 잔존 / push-to-start 되살림 = 배너(Apple 강제).
- **조회 실패(NOT_FOUND) 처리**: 등록 시 force 미지정이면 422 → 앱이 확인 다이얼로그. 등록 후 데이터 없으면 앱에서 "확인 중"(12h 경과 시 "번호 확인 필요") 회색 표시.

---

## 택배사 API (tracker.delivery)

- 한국 택배사는 공식 개인 개발자 API 없음 → **tracker.delivery(Delivery Tracker) GraphQL** 사용
- 인증: `TRACKQL-API-KEY {clientId}:{clientSecret}`. **무료 티어 credential 은 21일마다 콘솔에서 수동 재발급** → `admin.ts` 페이지에서 갱신
- 사용 쿼리: `track`(상태 조회), `registerTrackWebhook`(Boolean 반환, expirationTime 필수, 48h TTL → 24h마다 keep-alive 갱신)
- webhook 콜백 payload 는 `{carrierId, trackingNumber}` 만 → 콜백 시 `track` 재조회로 상태 갱신
- 조회 안 되면 NOT_FOUND (잘못된 번호 / 배송준비중 / 데이터 만료를 API가 구분 못 함)

### 지원 택배사 (`server/src/types/delivery.ts` 의 `CARRIERS` 상수)
`id` (앱/DB 키) — `name` — `trackerId` (tracker.delivery 식별자)
1. cj — CJ대한통운 — kr.cjlogistics
2. hanjin — 한진택배 — kr.hanjin
3. lotte — 롯데택배 — kr.lotte
4. epost — 우체국택배 — kr.epost
5. logen — 로젠택배 — kr.logen
6. coupang — 쿠팡 — kr.coupangls

> 택배사는 코드 상수. 추가하려면 `CARRIERS` 에 `trackerId`(tracker.delivery 의 정확한 식별자)와 함께 추가.
> tracker.delivery 는 한국 외 글로벌 택배사도 지원하므로, API 동기화로 바꾸려면 `kr.` 필터 필요.

---

## 기기 대응

| 기기 | Dynamic Island | 대응 방식 |
|---|---|---|
| iPhone 14 Pro / 14 Pro Max | ✅ | 풀 경험 |
| iPhone 15 전 라인업 | ✅ | 풀 경험 |
| iPhone 16 전 라인업 | ✅ | 풀 경험 |
| 그 외 iPhone (노치/홈버튼) | ❌ | Lock Screen Widget으로 대체 |

- Dynamic Island 크기는 기기별로 다름 → 기기 분기 처리 필요
- Pro / Pro Max 너비 다름 주의

---

## 수익 모델 (Pixel Pals 참고)

| 티어 | 내용 | 가격 (예시) |
|---|---|---|
| 무료 | 기본 트럭 1종, 추적 2개 | 무료 |
| Waito Plus | 트럭 스킨 다수, 추적 무제한, 커스텀 애니메이션 | ₩2,900/월 or ₩19,900/년 |

- 트럭 스킨: 기본 트럭 / 귀여운 트럭 / 픽셀 트럭 / 시즌 한정 등
- 장기 리텐션을 위해 "택배 없을 때도 켜두고 싶은 기능" 추가 고려

---

## 구현 현황 (개발 완료)

### 목록 화면 (DeliveryListView / TrackingRowView)
- **택배사 선택**: 시스템 Menu 대신 픽셀 스타일 펼침 드롭다운(`PixelDropdown`)
- **추가 폼**: 인라인 폼(AddTrackingView 제거). 조회 실패(NOT_FOUND) 시 "그래도 추가" 확인 다이얼로그(`PixelConfirm`) → `force` 재요청
- **정렬**: 도착임박순(기본) / 최근 업데이트순 / 등록순 — 칩으로 선택, `@AppStorage` 영구 저장
- **행 슬라이드 삭제**: 왼쪽 슬라이드 → "> DEL _" 버튼(HStack 딸려나옴, 스프링/고무줄). 한 번에 하나만 열림(`openRowId` 공유), ADD 누르면 닫힘
- **조회 안 되는 운송장**: `last_event_time` 없으면 회색 + "확인 중", 등록 12시간 경과 시 "번호 확인 필요"(오렌지)
- **트럭 버튼**(우상단): 사용자가 선택한 트럭(`CatalogTruckView`)을 표시 — `TruckConfigStore` 변경 시 자동 갱신

### 설정 (SettingsView)
- (DEBUG) **테스트 데이터 토글**: 켜면 목록에 더미 택배 표시. 기존 "Dynamic Island 데모" 버튼은 제거
- **항상 노출 토글**(구독 전용): 배송이 없어도 Dynamic Island에 트럭 상시 표시. 무료는 회색 잠금+크라운, 탭 시 PaywallView. 동작 게이팅은 `TrackingService.ambientEnabled`(토글 && 구독) 이중 확인 — 배송 없을 때 ambient Live Activity(`pushType:nil`, 빈 items) 시작/종료. ⚠️ iOS 제약: Live Activity는 잠금화면 카드에도 함께 노출(DI 단독 표시 불가) → 위젯에 idle 뷰 추가. `PixelToggle`은 `isEnabled`로 비활성 표시.

### 트럭 꾸미기 (TruckCustomizeView)
- **픽셀 카탈로그(이미지 기반)**: cab 27 / body 33 / wheel 27 — 4계열(🚚트럭·🪖탱크·🚆기차·🏗️건설) 자유 조합 ≈ 24,057가지. `CatalogTruckView`가 `Image(에셋명)`으로 렌더(에셋: `Assets.xcassets/PixelCatalog/{Cabs,Bodies,Wheels}`, SVG). **enum rawValue = 에셋 imageset 이름과 1:1** → 이름 누락/불일치 시 트럭이 빈 화면이 됨(주의).
- **무료/유료**: 무료는 트럭 부품 일부만(헤드2/바디3/바퀴2 = 각 enum `freeCases` 화이트리스트). 탱크·물탱크(탱크로리)·기차·건설·컨테이너 + 나머지 트럭 부품은 Plus. 잠금 항목 탭 → `PlusPaywallView`(`showSubscriptionAlert` → `fullScreenCover`).
- cab/body/wheel 조합 → `TruckConfigStore`(UserDefaults). 변경 시 실행 중 Activity 갱신(`pushTruckConfig`) + 서버 push-to-start 설정 갱신(`refreshPushToStartConfig`)

### Live Activity 푸시 (서버 + iOS)
- APNs 실제 전송 + push-to-start 이벤트 기반 (위 "데이터 흐름" 참조)
- 무료 1개 / 유료 2개 추적 제한(`SubscriptionManager.liveActivityLimit`)

---

## 구현 우선순위

```
1단계: Live Activity 기본 틀 + 검정 배경 착시 확인
2단계: 트럭 아이콘 t값 기반 위치/회전 계산
3단계: 배송 단계 → t값 매핑 + 애니메이션
4단계: 택배사 API 연동 + 폴링
5단계: 수익 모델 (구독 + 트럭 스킨)
```

---

## 참고 레퍼런스

- **Pixel Pals** (Christian Selig) — Dynamic Island 착시 구현 방식
- **Apple ActivityKit 공식 문서** — Live Activity API
- **DeliveryTracker (tracker.delivery)** — 한국 택배사 비공식 API

## Skill routing

When the user's request matches an available skill, ALWAYS invoke it using the Skill
tool as your FIRST action. Do NOT answer directly, do NOT use other tools first.
The skill has specialized workflows that produce better results than ad-hoc answers.

Key routing rules:
- Product ideas, "is this worth building", brainstorming → invoke office-hours
- Bugs, errors, "why is this broken", 500 errors → invoke investigate
- Ship, deploy, push, create PR → invoke ship
- QA, test the site, find bugs → invoke qa
- Browser testing, screenshot, page interaction, headless browser, navigate URL → invoke gstack
- Code review, check my diff → invoke review
- Update docs after shipping → invoke document-release
- Weekly retro → invoke retro
- Design system, brand → invoke design-consultation
- Visual audit, design polish → invoke design-review
- Architecture review → invoke plan-eng-review
- Save progress, checkpoint, resume → invoke checkpoint
- Code quality, health check → invoke health
