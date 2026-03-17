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

## 프로젝트 구조

```
Waito/
├── App/
│   └── WaitoApp.swift
├── LiveActivity/
│   ├── DeliveryAttributes.swift        # ContentState 데이터 모델
│   └── WaitoLiveActivityView.swift     # Dynamic Island UI (착시 핵심)
├── Views/
│   ├── AddTrackingView.swift           # 운송장 번호 입력
│   └── DeliveryListView.swift          # 택배 목록
├── Models/
│   └── DeliveryStatus.swift            # 배송 단계 enum + t값 변환
├── Services/
│   └── TrackingService.swift           # 택배 조회 + 폴링
└── CLAUDE.md                           # 이 파일
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

### ActivityKit ContentState

```swift
struct DeliveryAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var status: DeliveryStatus
        var carrierName: String
        var itemName: String
        var estimatedDelivery: String?
    }
    var trackingNumber: String
}
```

---

## 데이터 흐름

```
앱 실행 or BGAppRefreshTask (백그라운드 폴링)
        ↓
TrackingService → 택배사 API 조회
        ↓
배송 단계 파싱 → DeliveryStatus로 변환
        ↓
상태 변경 감지?
  Yes → ActivityKit.update(ContentState) → 트럭 애니메이션
  No  → 다음 refresh 대기
```

---

## 택배사 API

- 한국 주요 택배사(CJ, 한진, 롯데)는 공식 개인 개발자 API 없음
- **추천 서드파티**: [스마트택배 비공식 API](https://tracker.delivery/) 또는 자체 크롤링
- API 장애 대비 fallback 처리 필수

### 지원 택배사 우선순위
1. CJ대한통운
2. 한진택배
3. 롯데택배
4. 우체국택배
5. 로젠택배

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
