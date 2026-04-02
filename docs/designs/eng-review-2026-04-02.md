# Eng Review 결과 (2026-04-02)

**VERDICT: CLEARED** — CEO Review + Eng Review 모두 통과

---

## 확정된 아키텍처

```
┌──────────┐   HTTPS   ┌──────────────┐   GraphQL   ┌──────────────┐
│  iOS App │ ◄───────► │  Express API │ ◄──────────► │ tracker.     │
│ (SwiftUI │           │  (Node.js)   │              │ delivery     │
│  + AKit  │  APNs     │  on Vultr    │              └──────────────┘
│  + SKt2) │ ◄──────── │  서울 리전    │
└──────────┘           │  Supabase PG │
                       │  (DB only)   │
                       └──────────────┘
```

### 기술 결정

| 결정 | 선택 | 이유 |
|---|---|---|
| APNs | Node.js http2 직접 구현 + jsonwebtoken | 외부 의존성 없이 ~50줄로 구현 가능 |
| DB | Supabase PostgreSQL + pg (node-postgres) | 무료 관리형 DB, Auth는 안 쓰고 DB만 사용 |
| 서버 호스팅 | Vultr 서울 리전 ($2.50/월) | 슬립 없음, 서울 리전으로 지연 낮음 |
| 인증 | deviceToken UUID (현재 방식 유지) | UUID 추측 불가능, Sign in with Apple 불필요 |
| Push 스키마 | push token을 devices 테이블로 이동 | 단일 Activity에 device의 모든 활성 택배를 items 배열로 묶어 push |
| DB 클라이언트 | getDb().prepare() → pool.query() | 현재 SQL 직접 쓰는 패턴과 가장 비슷, 최소 변경 |
| Live Activity 12시간 제한 | Activity 만료 시 자동 종료 + 재시작 | 택배 배송이 12시간 이상이므로 핵심 기능 |
| 데코 모드 push 빈도 | 4시간마다 push | Apple 예산 여유 있고 8시간 제한 내 갱신 |

---

## 확정된 구현 순서 (9단계)

1. **실기기 착시 검증** (TestFlight) — 최우선. 안 되면 나머지 의미 없음
2. **APNs 구현** + ContentState 스키마 통일 + Activity 자동 재시작
3. **SQLite → Supabase PostgreSQL** (pg)
4. **Vultr 서버 배포** (PM2 + Nginx + SSL)
5. **StoreKit 2 구독 연동**
6. **데코 모드** (4시간 주기 push)
7. **클립보드/OCR 운송장 인식**
8. **도착 축하 애니메이션** + 햅틱
9. **온보딩 플로우** (Dynamic Island 데모)

---

## 병렬 구현 전략

```
Lane C (검증): 착시 검증 ← 최우선, 단독
Lane A (서버): APNs → PG 전환 → Vultr 배포 → 데코 모드 push
Lane B (iOS):  StoreKit 2 | OCR | 축하 애니메이션 | 온보딩

실행: C 먼저. 검증 통과 후 A + B 병렬. 배포 후 통합 테스트.
```

---

## 스코프

### v1.0 포함
- StoreKit 2 구독 (₩2,900/월 or ₩19,900/년)
- 데코 모드 (구독자 전용)
- 클립보드/OCR 운송장 인식
- 도착 축하 애니메이션
- 온보딩 플로우
- Activity 자동 재시작 (12시간 제한 대응)

### NOT in scope
- Sign in with Apple (deviceToken UUID로 충분)
- Supabase Auth (불필요)
- 위젯 (Home/Lock Screen)
- Apple Watch
- 다국어 지원
- 시즌 한정 스킨
- 푸시 알림 커스터마이징

---

## 수익 모델 (CEO 리뷰에서 확정)

| | 무료 | Waito Plus |
|---|---|---|
| 트럭 스킨 | 기본 1종 | 프리미엄 전체 |
| Live Activity | 1개 | 2개 |
| 데코 모드 | X | O (택배 없어도 트럭이 달림) |
| 추적 | 무제한 | 무제한 |

---

## 기존 코드 재사용

| 기존 코드 | 재사용 |
|---|---|
| trackerApi.ts (GraphQL) | ✅ 그대로 |
| statusMapper.ts + 테스트 | ✅ 그대로 |
| pollingService.ts | ✅ 그대로 |
| credentialMonitor.ts + 테스트 | ✅ 그대로 |
| WaitoLiveActivityView.swift | ✅ 그대로 |
| TruckPathCalculator | ✅ 그대로 |
| SubscriptionManager.swift | ✅ 로직 유지, StoreKit 연동만 |
| pushService.ts | ❌ 스텁, 완전 재작성 |
| database.ts | ❌ SQLite→PG 전환 |

---

## 테스트 계획

현재 21% → 목표 80%

범위: 전체 서버 (단위 + API 라우트 통합)
- pushService 재작성 테스트 (HTTP/2, JWT, 재시도, token 무효화)
- trackerApi 401 처리 테스트
- pollingService 상태 변경 테스트
- 전체 API 라우트 통합 테스트 (supertest + vitest)

---

## Critical GAP (4개)

1. APNs HTTP/2 연결 실패 → 사용자에게 조용한 실패
2. APNs JWT 토큰 만료 → push 전체 중단
3. Live Activity 재시작 실패 → 트럭 사라짐
4. StoreKit 2 결제 실패 → 구독 불가

→ 구현 시 반드시 에러 핸들링 + 테스트 추가 필요

---

## 비용 구조

| 항목 | 월 비용 |
|---|---|
| Vultr VPS (서울) | $2.50 |
| Supabase PostgreSQL | 무료 (500MB) |
| Apple Developer | 약 ₩1만 (연 ₩13만) |
| **총 고정비** | **약 ₩4.5만/월** |

---

## Outside Voice 주요 발견

| 이슈 | 판단 | 조치 |
|---|---|---|
| 12시간 Live Activity 제한 | 유효 | Activity 자동 재시작 (핵심 기능) |
| Supabase + Vultr 이중 인프라 | 유효 | Supabase는 DB만 사용, Auth 제거 |
| 인증 전 공개 API | 유효 | deviceToken UUID로 충분 |
| ContentState 4KB 제한 | 무해 | 택배 2개 + truckConfig ≈ 500B |
| 테스트 80% 비현실적 | 유효 | 핵심 서비스 우선, 기능과 병행 |

---

## Review Dashboard

```
+====================================================================+
|                    REVIEW READINESS DASHBOARD                       |
+====================================================================+
| Review          | Status         | Required |
|-----------------|----------------|----------|
| Eng Review      | CLEAN (PLAN)   | YES ✅   |
| CEO Review      | CLEAN          | no  ✅   |
| Design Review   | —              | no       |
| Outside Voice   | ISSUES (해결됨) | no       |
+--------------------------------------------------------------------+
| VERDICT: CLEARED                                                    |
+====================================================================+
```

---

## 다음 단계

1. 착시 검증 (TestFlight) → 최우선
2. 검증 통과 후 서버/iOS 병렬 구현
3. Vultr 배포 → 통합 테스트
4. App Store 제출
