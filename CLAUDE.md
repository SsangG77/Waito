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
│       └── RunningTruckScene.swift      # RunningTruckView: 트럭 바운스+속도선 "달리는" 효과 래퍼(@ViewBuilder), 위젯 타깃 공유 / Color(hex:UInt32)
├── Models/
│   ├── DeliveryStatus.swift            # 배송 단계 enum(String raw) + t값/회전각
│   ├── TruckConfig.swift, TruckConfigStore.swift
│   ├── PixelTruckCatalog.swift         # cab27/body33/wheel27 enum, rawValue=에셋 imageset명, requiresPlus 화이트리스트
│   └── API/APIModels.swift             # Carrier, TrackingListItem, 요청/응답 DTO
├── Services/
│   ├── TrackingService.swift           # @Observable 상태관리 + Live Activity + push 토큰 관찰
│   ├── APIClient.swift                 # actor, 서버 REST 호출
│   ├── StoreKitService.swift           # StoreKit2 접근(상품 로드/purchase/restore/entitlement) — SwiftUI 비의존
│   └── SubscriptionManager.swift       # @Observable, 실구독(entitlement)+디버그언락 결합 → isSubscribed
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
│   ├── trackings.ts                    # 택배 CRUD(PUT /:id = 품명·메모 수정) + push-token 등록 + force 추가
│   ├── devices.ts                      # 디바이스 등록 + push-to-start-token + PUT /apns-token(일반알림) + GET /me(포인트) + POST /unlock-part
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
    // 가변 이벤트 타임라인 compact 필드(위젯 타깃은 TrackingEvent 전체를 못 봄). 전부 Optional(하위호환).
    var eventCount: Int?       // 원본 이벤트 개수 → 점 개수(가변). nil/0 이면 status 기반 7단계 폴백
    var statusLabel: String?   // 마지막 이벤트 원본 description. nil 이면 status.displayName
    var departureDate: String? // 목록 createdAt(출발/등록일). 위젯에서 "YYYY.MM.DD"로 표시
    var truckBounce: Double?   // idle 트럭 y오프셋(LA bounce). > BOUNCE 버튼이 갱신
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
> **신규 필드는 반드시 Optional** — 기본값을 주면 합성 Codable 이 키를 필수로 간주해 구 payload/persisted Activity 디코딩이 실패함.
> `eventCount`/`statusLabel`/`departureDate` 는 iOS `buildContentState` 와 서버 `pushService` 둘 다 동일하게 채움.

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
  - sandbox/production 은 `APNS_PRODUCTION` 로 전환. `apnsClient.sendPush(generic)` → LA: push-type `liveactivity` + topic `<bundleId>.push-type.liveactivity` / 일반 알림: `sendAlertPush` push-type `alert` + topic `<bundleId>`.
- **세 종류 토큰**: update 토큰(Activity 인스턴스당, 갱신용) / push-to-start 토큰(디바이스당, 되살리기용, iOS 17.2+) / **표준 원격알림 토큰(`devices.apns_token`, 일반 배너용)**.
  - 앱이 `Activity.pushToStartTokenUpdates` 관찰 → `truckConfig` 와 함께 서버 등록. 표준 토큰은 `AppDelegate.didRegisterForRemoteNotifications` → `PUT /api/devices/apns-token`(ContentView.task 의 `syncAPNsToken` 재시도 경로 병행).
- **8시간 한도 대응**: Live Activity 는 8h 후 시스템이 종료. 별도 타이머 없이 **상태 변경 시점에** 죽었으면 push-to-start 로 되살리는 이벤트 기반.
- **알림 정책**: 상태 변경당 **배너 정확히 1개**. LA 중간 update = 무음 / 배송완료 end = 배너 / push-to-start 되살림 = 배너(Apple 강제). **그 외(LA가 배너 안 띄운 모든 경우) = 표준 일반 알림(`sendStatusAlert`)** 으로 배너 — LA 미사용 택배 포함 모든 택배가 상태 변경 시 알림 받음. `pushService` 의 `bannerShown` 플래그로 중복 방지.
  - ⚠️ 표준 원격알림은 Xcode **Push Notifications capability(aps-environment entitlement)** 필요.
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

> 가격: 코드/StoreKit 기준 **₩3,000/월**(상품 `com.sangjin.Waito.plus.monthly`). 페이월은 "하루 ₩110" 마케팅 표기 + 실제 월가격 병기. (노션 Lean Canvas 와 불일치 시 ASC 등록가 기준으로 통일 필요)

| 티어 | 내용 | 가격 |
|---|---|---|
| 무료 | 기본 트럭 + Live Activity 1개 + 배송완료 포인트로 트럭 계열 부품 해제(3P/개) | 무료 |
| Waito Plus | 프리미엄 스킨(탱크·기차·물탱크·건설·컨테이너) 즉시 전부 + Live Activity 2개 + 데코(항상 노출) | ₩3,000/월 |

### StoreKit 구독 (실제 결제)
- **상품**: 월간 자동갱신 `com.sangjin.Waito.plus.monthly`(₩3,000) — 가격은 App Store Connect 에서 설정. 로컬 테스트는 `ios/Waito/Waito.storekit`(Xcode 수동 추가 + Scheme 지정).
- **`StoreKitService`**(StoreKit2): `loadProducts`/`purchase`(검증·finish)/`restore`(AppStore.sync)/`isEntitled`(currentEntitlements)/`observeTransactionUpdates`.
- **`SubscriptionManager`**: `isSubscribed = isStoreSubscribed(entitlement) || isDebugUnlocked`. 앱시작 `start()` 로 상품로드+권한확인+트랜잭션 관찰. `purchaseMonthly()`/`restore()`/`refreshEntitlement()`. 디버그 언락은 `debug_unlocked` 키로 **실구독과 완전 분리**(디버그 끄기가 실구독 안 끔). 결합값을 `waito_is_subscribed` 키에 미러(TrackingService/위젯 재확인용).
- **페이월 구매 동선**: `PlusPaywallView` "구독 시작하기" → `purchaseMonthly()`(Apple 결제 시트 즉시) + 복원 버튼. `PaywallView`(StoreKit `SubscriptionStoreView`)는 `PlusMarketingHero` 공유 + `containerBackground`로 다크. 두 페이월 모두 `@Environment(SubscriptionManager.self)` → 시트/커버에 **명시 재주입 필수**(자동 전파 보장 안 됨).
- ⚠️ ASC 상품 미등록/유료앱계약 미체결이면 `monthlyProduct=nil` → 구매 버튼 무동작.
- **페이월 UX 보강**: 구매 결과 `PurchaseOutcome`(success/cancelled/failed/unavailable) — 진짜 실패만 오류 알림(취소는 조용히). 이미 구독 중이면 CTA 대신 "이미 이용 중" 표시. 상품 로딩 전이면 CTA 비활성("상품 불러오는 중…").
- **오퍼 코드(특가 코드, 예 `monthly_free` 첫해 무료)**: 페이월 하단 "프로모션 코드" → `.offerCodeRedemption`(Apple 공식 입력 시트, 인앱 직접 입력칸은 불가). 성공 시 `refreshEntitlement`. `import StoreKit` 필요. ⚠️ ASC "구독 프로모션"이 진행 중이어야 코드 적용됨. TestFlight/실기기에서만 테스트.

- **포인트 경제**: 배송완료 1건 = 1P, 부품 1개 해제 = 3P(차감형). 탱크·기차·물탱크·건설·컨테이너는 **Plus 전용**(포인트 불가, 트럭 계열만 포인트 해제)
- 장기 리텐션: "택배 없을 때도 켜두고 싶은 기능"(데코/시즌 스킨) + 포인트 보상

---

## 구현 현황 (개발 완료)

### 목록 화면 (DeliveryListView / TrackingRowView)
- **택배사 선택**: 시스템 Menu 대신 픽셀 스타일 펼침 드롭다운(`PixelDropdown`)
- **추가 폼**: 인라인 폼(AddTrackingView 제거). 조회 실패(NOT_FOUND) 시 "그래도 추가" 확인 다이얼로그(`PixelConfirm`) → `force` 재요청
- **정렬**: 도착임박순(기본) / 최근 업데이트순 / 등록순 — 칩으로 선택, `@AppStorage` 영구 저장
- **완료 섹션 구분**: 배송완료(`currentStatus.isCompleted`) 항목은 리스트 아래 **"완료 N" 섹션**으로 분리(`activeTrackings`/`completedTrackings`, 각 그룹 안에서 현재 정렬 적용). 헤더 탭으로 접기/펼치기(`@AppStorage("completed_section_collapsed")`, 기본 접힘). 완료 없으면 섹션 숨김.
- **행 슬라이드 → 삭제/수정**: 왼쪽 슬라이드 → "> DEL_"(빨강)·"> EDIT_"(오렌지) **2버튼 세로 분할**(각 절반 높이, 스프링/고무줄). 한 번에 하나만 열림(`openRowId` 공유), 바깥 탭/ADD 누르면 닫힘.
  - **삭제**: 탭 시 즉시 삭제 X → 상위(`DeliveryListView`)에서 `PixelConfirm`("삭제하면 되돌릴 수 없어요") 한 번 더 확인 후 `service.deleteTracking`. (확인 팝업은 전체화면 오버레이라 행이 아닌 상위에 부착)
  - **수정(EDIT)**: 탭 시 상단 입력 폼이 **편집 모드**로 열리며 기존 값 prefill. 운송장번호/택배사는 '신원'이라 **읽기전용**(회색), **품명·메모만 수정**. 제출 버튼 라벨이 ADD→**EDIT**. `service.updateTracking`(PUT /api/trackings/:id) 호출. (`editingTrackingId`로 add/edit 분기)
- **추가 직후 강조**: 새로 추가된 행이 한 번 통통 바운스(`justAddedId` → `scaleEffect` 스프링). 사용자가 추가됨을 인지.
- **메모(memo)**: 추가/수정 시 입력, 펼친 상세에 "MEMO" 표시. **풀스택 영속**(DB `trackings.memo` 컬럼 + 서버 create/update/list 반영 + `TrackingListItem.memo`).
- **조회 안 되는 운송장**: `last_event_time` 없으면 회색 + "확인 중", 등록 12시간 경과 시 "번호 확인 필요"(오렌지)
- **트럭 버튼**(우상단): 사용자가 선택한 트럭(`CatalogTruckView`)을 표시 — `TruckConfigStore` 변경 시 자동 갱신
- **빈 상태(택배 0개)**: 빈 화면 대신 `emptyState` — 사용자가 고른 트럭이 화면 가운데서 `RunningTruckView`로 "달리는" 효과(인앱이라 연속 애니메이션 정상 재생) + 위쪽 `chevron.up`과 "위 ADD 버튼으로 택배를 추가해보세요" 안내(상단 ADD 버튼을 가리킴, 중복 버튼 없음). pull-to-refresh 유지.
- **첫 추가 업셀 페이월**: 첫 택배 추가 성공 직후 `PlusPaywallView`를 풀스크린 1회 노출. 평생 1회(`@AppStorage("has_shown_first_add_paywall")`) + 비구독자(`subscription.isSubscribed == false`) 한정(`maybeShowFirstAddPaywall()`). 콜드 첫 화면 하드 페이월 대신 "가치 경험(첫 추가) 직후" 노출 정책.

### 설정 (SettingsView)
- (DEBUG) **테스트 데이터 토글**: 켜면 목록에 더미 택배 표시. 기존 "Dynamic Island 데모" 버튼은 제거
- **항상 노출 토글**(구독 전용): 배송이 없어도 Dynamic Island에 트럭 상시 표시. 무료는 회색 잠금+크라운, 탭 시 PaywallView. 동작 게이팅은 `TrackingService.ambientEnabled`(토글 && 구독) 이중 확인 — 배송 없을 때 ambient Live Activity(`pushType:nil`, 빈 items) 시작/종료. ⚠️ iOS 제약: Live Activity는 잠금화면 카드에도 함께 노출(DI 단독 표시 불가) → 위젯에 idle 뷰 추가. 배송 없을 때 idle 표시: **접힘** = leading 트럭 / trailing 없음, **펼침·잠금화면** = `RunningTruckView`(달리는 효과). `PixelToggle`은 `isEnabled`로 비활성 표시. (`RoamingTruckView`는 좌우 왕복 컴포넌트로 `CompactIslandViews.swift`에 남아 있으나 현재 미사용.)

### 트럭 꾸미기 (TruckCustomizeView)
- **픽셀 카탈로그(이미지 기반)**: cab 27 / body 33 / wheel 27 — 4계열(🚚트럭·🪖탱크·🚆기차·🏗️건설) 자유 조합 ≈ 24,057가지. `CatalogTruckView`가 `Image(에셋명)`으로 렌더(에셋: `Assets.xcassets/PixelCatalog/{Cabs,Bodies,Wheels}`, SVG). **enum rawValue = 에셋 imageset 이름과 1:1** → 이름 누락/불일치 시 트럭이 빈 화면이 됨(주의).
- **부품 등급(`PartTier`, PixelTruckCatalog)**: 3단계.
  - **무료**: 각 enum `freeCases`(헤드2/바디3/바퀴2)
  - **포인트 해제(`pointUnlockable`, 비용 `pointUnlockCost`=3)**: 트럭 계열 추가 부품만(에셋명 2번째 토큰 `TruckHead`/`Truck`/`Wheels`). 배송완료 포인트로 해제.
  - **Plus 전용(`plusOnly`, 포인트로도 불가)**: 탱크·기차·물탱크(탱크로리)·건설·컨테이너(`TankGun/Tank/TankTrack/Train/LiquidTank/Construction/ConstructionTrack/Container`)
- **포인트 경제**: 배송완료 1건=1포인트(디바이스별, 서버 `devices.delivered_count`). 부품 1개 해제=3포인트(서버 `devices.unlocked_parts` JSON). 잔액 = 누적−해제수×3. `TrackingService.pointBalance/isUnlocked/loadDeviceProgress/unlockPart`. delivered 전환 +1은 `pollingService`, 해제 검증(Plus계열 403/잔액 400)은 `devices.ts` POST `/unlock-part`. ⚠️ 디바이스 단위(키체인 토큰) — 기기 간 동기화는 2차 로그인.
- **My Truck 게이팅**: 셀 잠금 = 무료/구독이면 없음, `pointUnlockable` 미해제면 "3P"(코인), `plusOnly`면 크라운. 저장 시 `handleSave` — Plus전용 끼면 페이월, 포인트대상이면 `PixelConfirm`로 N×3P 차감 후 커밋. **포인트 부족 시 중간 안내 없이 바로 `PlusPaywallView` 직행** — 페이월 가격 위에 보유/부족 포인트 표시(`PlusPaywallView.pointStatus`, 옵셔널이라 잠금탭·첫추가 업셀 등 다른 진입점은 미표시).
- cab/body/wheel 조합 → `TruckConfigStore`(UserDefaults). 변경 시 실행 중 Activity 갱신(`pushTruckConfig`) + 서버 push-to-start 설정 갱신(`refreshPushToStartConfig`)

### Live Activity 푸시 (서버 + iOS)
- APNs 실제 전송 + push-to-start 이벤트 기반 (위 "데이터 흐름" 참조)
- 무료 1개 / 유료 **2개** 추적 제한(`SubscriptionManager.liveActivityLimit`). 잠금화면은 토글된 전부를 `ForEach`로 표시(primary+secondary 고정 아님). 한도 도달 시 무료는 Plus 페이월, 유료는 "표시 제한" 안내 팝업(`showLiveActivityLimitAlert`). ⚠️ ActivityKit ContentState 4KB·잠금화면 높이 제약상 상한 둠.
- **트럭 표시(위젯)**: 접힌 DI(compact leading)·잠금화면 배송 행은 **`CatalogTruckView` 트럭만** 정적 표시. **잠금화면 idle 과 펼친 DI idle(배송 없음 + 항상노출)은 동일한 `LockScreenIdleRow`(좌측 트럭 + `> BOUNCE_` 버튼) 공유** — `ExpandedMetroTimelineView.idleContent` 가 그대로 재사용.
  - ⚠️ **iOS 제약**: Live Activity(잠금화면/DI)는 시스템이 SwiftUI 애니메이션 모디파이어를 무시 → `repeatForever` 등 연속 애니메이션이 **실기기/시뮬에서 안 돎**(공식 문서 "Animating data updates in widgets and Live Activities"). 위젯에선 **오직 content state(ContentState) 변경 시에만** 화면이 갱신됨. → 위젯에선 자율 애니메이션 효과를 쓰지 않음.
    - **실기기 검증 결과(2026-06)**: idle 트럭을 "스스로 움직이게" 하려는 3가지 시도 모두 정지 확인 — ①`ProgressView(timerInterval:)`+커스텀 `ProgressViewStyle`(시스템이 `fractionCompleted` 를 커스텀 스타일에 안 흘려줌), ②`PhaseAnimator`(위젯에서 순환 안 함), ③`repeatForever`+`onAppear`(트리거 미발동). **자동 동력이 필요하면 서버 push 뿐이나 APNs Live Activity update 는 15초 throttle → walk-cycle 불가.** 결론: idle 트럭은 정적 + `> BOUNCE` 버튼(탭=state 변경)으로만 움직임.
  - **`RunningTruckView`(`RunningTruckScene.swift`)**: 트럭 바운스+속도선 "달리는" 효과 래퍼(`animated` 플래그). **인앱/프리뷰 전용**(일반 SwiftUI라 정상 재생). 현재 **목록 빈 상태(DeliveryListView)** 에서 사용. 모션은 `TimelineView(.animation)` 공유 시간축 + 위상(phase) 기반 — 각 속도선이 항상 화면 전체에 균등 분배돼 우→좌로 흐름(이전 `repeatForever`+`delay` 방식의 뭉침/트럭 뒤 출현 문제 해결). `Color(hex: UInt32)` 포함. 위젯에선 미사용.
  - (`RoamingTruckView` 좌우 왕복도 `CompactIslandViews.swift`에 미사용 잔존.)

### 가변 이벤트 타임라인 (고정 7단계 폐기)
- 진행 타임라인 점 개수 = **실제 택배사 이벤트 개수**(가변). 라벨 = 원본 `description`. 이벤트만 표시(전부 지나감, 트럭은 마지막 점). 이벤트 없으면 status 기반 7단계 폴백.
- 데이터: 서버 `GET /api/trackings` 목록이 각 택배의 `events` 전체 포함(`TrackingListItem.events`). LA는 위젯 타깃이 `TrackingEvent`를 못 보므로 **compact 필드(`eventCount`/`statusLabel`)만** 전달.
- 인앱: 접힘 가로바·펼침 세로 타임라인 모두 `TrackingRowView`에서 events 기반. 펼침은 점마다 `description` 라벨.
- 위젯: 잠금화면 `LockScreenStatusTimeline`(가변 점, 상한 14), DI 펼침 `ExpandedMetroTimelineView`(center=물품명+타임라인, bottom=출발날짜 ⟷ 상태라벨).
- `ExpandedTruckPathView`(폐기된 Island Circuit 1차 디자인) 삭제됨.

### 잠금화면 idle (항상 노출)
- 좌측 정적 트럭 + 우측 **`> BOUNCE` 버튼**(`BounceTruckIntent: LiveActivityIntent`). 탭 시 트럭 y오프셋(`truckBounce`)을 단계 갱신 → **8비트풍 스냅 바운스**(위젯 트럭에 `.animation(nil)`). `BounceGate` 액터로 진행 중 재탭 무시.
- BOUNCE 버튼 외형 = 앱 빨강 ADD 버튼과 동일한 픽셀 박스. 앱 `PixelTheme` 는 위젯에서 못 쓰므로 `WaitoWidgetColors.swift` 에 self-contained 복제(`wPixelBox`/`wPixelRed`/`WNotchedRectangle`/`WPixelBorderShape`).
- 배경 = `Color("bg")`(에셋), idle 카드 세로 꽉 채움.
- **픽셀 폰트 Galmuri9**: `pixelFont(_:)` 가 `PixelFont.swift`(앱·위젯 공유)로 이동, `Font.custom("Galmuri9-Regular")`. `Fonts/Galmuri9.ttf` + 두 타깃 `UIAppFonts` 등록.

### 디버그
- DEBUG 빌드에선 오류 팝업 억제(`DeliveryListView`에서 `showError` 게이팅) — 로컬 서버 미가동 시 네트워크 오류 팝업 방지.
- **테스트 운송장 `test970719`**(서버 `trackerApi.ts`/`pollingService.ts`): tracker.delivery 실제 조회 없이 더미 배송 데이터 응답. **`created_at` 기준 2시간마다 1단계 전진**(접수→집화→간선상차→간선하차→배송출발→배송중→배송완료), **배송완료 후 2시간 뒤 접수로 순환**(전체 14h 주기). 일반 폴링과 달리 전진 제약(`resolveNewStatus`)·`delivered_at` 설정 없이 `pollTestTracking` 으로 처리하고, 30분 cron 폴링에 상태 무관 항상 포함. webhook 등록도 skip. 빠른 확인은 `TEST_STEP_INTERVAL_MS` 를 임시 단축.
- **관리자 모드(릴리즈에서도 동작)**: `SettingsView` 버전 박스 **5탭 → 비밀번호 `970719`** 입력 시 ON(`@AppStorage("admin_mode")`). 효과 = **디버그 토글(TEST DATA / DEBUG SUBSCRIPTION)만 노출**(`showDebugTools = DEBUG || adminMode`). 더미·구독을 자동으로 켜지 않고 사용자가 토글로 직접 제어. **켜진 상태에서 버전 5탭 재실행 → OFF**: 토글 숨김 + 켜뒀던 효과 원복(`showDummyData=false`, `setDebugUnlocked(false)`). 토글 정의/게이팅(`dummyTrackings`/`showDummyData`)은 `#if DEBUG` 밖이라 릴리즈에서도 동작. ⚠️ `admin_mode`(UI 가시성)와 `debug_unlocked`(유료 해제, DEBUG SUBSCRIPTION 토글이 제어)는 **별도 키로 분리** — 실구독과도 무관(`setDebugUnlocked` 가 실구독을 끄지 않음). 항상노출은 구독 게이팅이라 DEBUG SUBSCRIPTION 을 켜야 실제 동작.

---

## 배포 / 운영 (실제)
- **서버**: Vultr 인스턴스 `158.247.223.154`(Ubuntu, 기존 brawlytics와 공존). Waito는 **포트 3001**, pm2 `waito`, `/var/www/waito/server`(repo sparse-checkout: `server/`만). `APNS_PRODUCTION=true`.
- **앱 ↔ 서버**: RELEASE `APIClient.baseURL = http://158.247.223.154:3001` (도메인/HTTPS 미사용 → `Info.plist` ATS `NSAllowsArbitraryLoads`). DEBUG는 로컬 IP.
  - ⚠️ **ATS 함정**: `NSAllowsArbitraryLoads` 와 `NSAllowsLocalNetworking` 을 **함께** 넣으면 iOS 10+ 에서 세분화 키(LocalNetworking)가 우선 적용되어 ArbitraryLoads 가 무시됨 → 사설 IP만 허용, **공인 IP(운영 서버) 차단**. DEBUG(사설 IP)는 통과·Release/TestFlight(공인 IP)만 네트워크 오류 나는 원인이었음. → `NSAllowsArbitraryLoads` **단독**으로 유지.
- **자동배포**: `.github/workflows/deploy.yml` — `server/**` push 시 GitHub Actions가 SSH로 Vultr 접속 → `git pull && npm ci && build && pm2 restart`. 시크릿 `VULTR_SSH_KEY`/`VULTR_HOST`.
- ⚠️ **브랜치 정책**: `main` 직접 푸시 금지 — push 시 자동배포가 트리거됨. 모든 작업은 **`dev` 브랜치**에 커밋·푸시하고, 검증 후 main 으로 머지(배포)한다.
- **credential 만료 알림**: 만료 3일 전부터 매일 이메일(`emailService` = Resend HTTP API, `RESEND_API_KEY`). 메일에 운영 admin 갱신 링크(시크릿 포함) 버튼.
- `.env`/`certs/*.p8`/`*.ttf 위치` 주의: `.env`·`certs/`는 gitignore — 서버엔 scp로 직접.

---

## Swift 동시성 / 빌드 설정

- **`SWIFT_DEFAULT_ACTOR_ISOLATION = nonisolated`** (`project.pbxproj` 4개 빌드설정). Xcode가 한때 이를 `MainActor` 로 자동 설정 → 모든 타입이 암묵적 `@MainActor` 가 되어, `actor APIClient`/위젯 `BounceTruckIntent` 가 데이터 모델(DTO·`DeliveryAttributes`)의 MainActor 격리 conformance 와 충돌(Swift 6 모드 에러). `nonisolated` 로 되돌려 해결.
- 대신 UI 상태관리 클래스는 **`@MainActor` 명시**: `TrackingService`·`TruckConfigStore`·`SubscriptionManager`(모두 `@Observable`). 데이터 모델/DTO 는 격리 없음 → actor·위젯 어디서든 인코딩/디코딩 가능.
- ⚠️ 새 `@Observable` 상태관리 클래스 추가 시 `@MainActor` 를 직접 붙일 것(자동 추론 없음).

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
- 노션 프로젝트에 할일/태스크 등록 → invoke project-task-add
  - 한국어 트리거(아래 표현이면 직접 답하지 말고 무조건 project-task-add 호출):
    "이거 (어떤) 프로젝트에 할일로 추가해줘", "OO 프로젝트에 OO 작업 등록", "할일 만들어줘",
    "노션에 태스크 추가", "이거 할일로 등록", "process database에 추가"
  - 대상 프로젝트가 불명확하면 스킬 실행 중 사용자에게 어떤 프로젝트인지 물어 진행
