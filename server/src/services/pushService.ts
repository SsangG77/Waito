import { DeliveryStatus } from '../types/delivery.js';
import { getDb } from '../db/database.js';
import { sendLiveActivityPush, sendAlertPush, LIVE_ACTIVITY_TOPIC, type ApnsResult } from './apnsClient.js';
import { config } from '../config.js';

/**
 * iOS DeliveryAttributes.ContentState 와 정확히 일치해야 하는 구조.
 * (키/타입 불일치 시 시스템이 디코딩에 실패해 업데이트가 무시됨)
 *   ContentState { items: [TrackingItemState], truckConfig: TruckConfig }
 *   TrackingItemState { trackingNumber, status, carrierName, itemName, estimatedDelivery,
 *                       eventCount, statusLabel }
 *
 * eventCount/statusLabel 은 가변 이벤트 타임라인용 compact 필드(위젯 타깃은
 * TrackingEvent 전체를 못 보므로 개수 + 최신 라벨만 전달). iOS 에선 Optional.
 */
interface TrackingItemState {
  trackingNumber: string;
  status: DeliveryStatus;
  carrierName: string;
  itemName: string;
  estimatedDelivery: string | null;
  eventCount: number;
  statusLabel: string | null;
  departureDate: string | null;
}

const STATUS_DESCRIPTIONS: Record<DeliveryStatus, string> = {
  [DeliveryStatus.Registered]: '택배가 접수되었습니다',
  [DeliveryStatus.PickedUp]: '택배가 집화 완료되었습니다',
  [DeliveryStatus.InTransitIn]: '택배가 간선상차 되었습니다',
  [DeliveryStatus.InTransitOut]: '택배가 간선하차 되었습니다',
  [DeliveryStatus.OutForDelivery]: '배송이 출발했습니다',
  [DeliveryStatus.Delivering]: '택배가 배송중입니다',
  [DeliveryStatus.Delivered]: '택배가 배송 완료되었습니다',
};

// 토큰 무효화는 reason === 'Unregistered'(앱 삭제 등)일 때만 수행한다.
// BadDeviceToken 은 sandbox/production 환경 불일치로도 발생하므로 즉시 무효화하지 않는다(정상 토큰 보호).

/** truck_config JSON 문자열을 content-state.truckConfig 객체로 (실패 시 undefined → iOS .default) */
function safeParseJson(s: string | null): Record<string, unknown> | undefined {
  if (!s) return undefined;
  try {
    return JSON.parse(s);
  } catch {
    return undefined;
  }
}

/** SQLite datetime('now') 문자열("YYYY-MM-DD HH:MM:SS", UTC)을 epoch ms 로 변환 */
function parseSqliteUtc(s: string | null): number {
  if (!s) return 0;
  const ms = Date.parse(s.replace(' ', 'T') + 'Z');
  return Number.isNaN(ms) ? 0 : ms;
}

/** Live Activity 최대 활성 시간 (Apple: 8시간) */
const ACTIVITY_MAX_MS = 8 * 60 * 60 * 1000;

function buildContentState(
  items: TrackingItemState[],
  truckConfig: Record<string, unknown> | undefined,
): Record<string, unknown> {
  // truckConfig 가 없으면 키를 생략 → iOS ContentState 의 기본값(.default) 사용
  return truckConfig ? { items, truckConfig } : { items };
}

// ── update / end ────────────────────────────────────────────

/**
 * 실행 중인 Live Activity 를 update/end 한다. (update 토큰 사용)
 */
export async function sendLiveActivityUpdate(
  pushToken: string,
  items: TrackingItemState[],
  truckConfig: Record<string, unknown> | undefined,
  isEnd: boolean,
): Promise<ApnsResult> {
  const now = Math.floor(Date.now() / 1000);
  const aps: Record<string, unknown> = {
    timestamp: now,
    event: isEnd ? 'end' : 'update',
    'content-state': buildContentState(items, truckConfig),
  };

  if (isEnd) {
    // 배송 완료(도착)를 배너로 알린 뒤, LA/DI 카드는 즉시 제거한다.
    // (dismissal-date 를 현재 시각으로 두면 시스템이 도착 푸시 수신 즉시 카드를 내림)
    aps.alert = {
      title: '배송 완료',
      body: items[0]?.statusLabel
        ?? (items[0] ? STATUS_DESCRIPTIONS[items[0].status] : STATUS_DESCRIPTIONS[DeliveryStatus.Delivered]),
    };
    aps['dismissal-date'] = now;  // 즉시 삭제(도착 시 LA/DI 에서 바로 사라지게)
  }
  // update(중간 상태 변경)는 alert 없이 화면만 조용히 갱신 (배너 알림 없음)

  // update/end 모두 오프라인 대비 1시간 보관/재시도.
  // (end 를 expiration=0 으로 보내면 오프라인 시 폐기되어 완료 배너가 누락될 수 있어 보관한다)
  const result = await sendLiveActivityPush({
    deviceToken: pushToken,
    payload: { aps },
    priority: 10,
    expiration: now + 60 * 60,
  });
  return result;
}

/**
 * 추적 ID 의 현재 상태로 Live Activity 를 갱신한다. (배송 상태 변경 시 호출)
 *
 * - Activity 가 살아있을 때(시작 후 8시간 미만): update 로 화면 갱신
 * - Activity 가 죽었을 때(8시간 경과/미시작) 또는 update 실패: push-to-start 로 되살림
 *
 * 별도의 8시간 재시작 타이머를 두지 않고, "상태가 바뀌는 순간"에만 (재)시작하므로
 * 의미 없는 재시작 알림이 발생하지 않는다. (완료 상태는 굳이 되살리지 않음)
 */
function parseIdArray(raw: string | null): number[] {
  if (!raw) return [];
  try {
    const v = JSON.parse(raw);
    return Array.isArray(v) ? v.filter((n): n is number => Number.isInteger(n)) : [];
  } catch {
    return [];
  }
}

export async function pushTrackingUpdate(changedTrackingId: number, changedStatus: DeliveryStatus): Promise<void> {
  const db = getDb();

  // 바뀐 택배가 속한 디바이스 + 디바이스 단위 Live Activity 정보(단일 LA 토큰 + 담긴 택배 id 목록)
  const dev = db
    .prepare(
      `SELECT d.id AS device_id, d.device_token, d.push_to_start_token, d.truck_config,
              d.apns_token, d.live_activity_push_token AS la_token, d.la_tracking_ids,
              t.item_name AS changed_item_name, t.carrier_name AS changed_carrier,
              (SELECT e.description FROM tracking_events e WHERE e.tracking_id = t.id
                 ORDER BY e.event_time DESC LIMIT 1) AS changed_label
       FROM trackings t JOIN devices d ON d.id = t.device_id
       WHERE t.id = ?`,
    )
    .get(changedTrackingId) as
    | {
        device_id: number;
        device_token: string;
        push_to_start_token: string | null;
        truck_config: string | null;
        apns_token: string | null;
        la_token: string | null;
        la_tracking_ids: string | null;
        changed_item_name: string;
        changed_carrier: string;
        changed_label: string | null;
      }
    | undefined;
  if (!dev) return;

  const truckConfig = safeParseJson(dev.truck_config);

  // LA 에 담긴 택배 전부를 순서대로 items 로 재구성 — 배송완료(도착)는 제외해 자동으로 사라지게 한다.
  const itemStmt = db.prepare(
    `SELECT tracking_number, current_status, carrier_name, item_name, estimated_delivery, created_at,
            (SELECT COUNT(*) FROM tracking_events e WHERE e.tracking_id = trackings.id) AS event_count,
            (SELECT e.description FROM tracking_events e WHERE e.tracking_id = trackings.id
               ORDER BY e.event_time DESC LIMIT 1) AS last_event_description
     FROM trackings WHERE id = ?`,
  );
  const items: TrackingItemState[] = [];
  for (const id of parseIdArray(dev.la_tracking_ids)) {
    const t = itemStmt.get(id) as
      | {
          tracking_number: string; current_status: DeliveryStatus; carrier_name: string;
          item_name: string; estimated_delivery: string | null; created_at: string | null;
          event_count: number; last_event_description: string | null;
        }
      | undefined;
    if (!t) continue;
    if (t.current_status === DeliveryStatus.Delivered) continue; // 도착 → LA 에서 제거
    items.push({
      trackingNumber: t.tracking_number,
      status: t.current_status,
      carrierName: t.carrier_name,
      itemName: t.item_name,
      estimatedDelivery: t.estimated_delivery,
      eventCount: t.event_count ?? 0,
      statusLabel: t.last_event_description ?? null,
      departureDate: t.created_at ?? null,
    });
  }

  let bannerShown = false;
  let laHandled = false;

  // 1) 디바이스 LA 갱신 토큰이 있으면 전체 items 로 한 번에 갱신(무음).
  //    items 가 비면(마지막 택배까지 도착) LA 를 종료 + 즉시 dismissal → 카드 삭제(배너 동반).
  if (dev.la_token) {
    if (items.length > 0) {
      const result = await sendLiveActivityUpdate(dev.la_token, items, truckConfig, false);
      if (result.ok || result.skipped) laHandled = true;
      else if (result.reason === 'Unregistered') {
        db.prepare('UPDATE devices SET live_activity_push_token = NULL WHERE id = ?').run(dev.device_id);
      }
    } else {
      const result = await sendLiveActivityUpdate(dev.la_token, [], truckConfig, true);
      if (result.ok) { laHandled = true; bannerShown = true; }  // end 페이로드가 배송완료 배너 동반
      else if (result.skipped) laHandled = true;
      else if (result.reason === 'Unregistered') {
        db.prepare('UPDATE devices SET live_activity_push_token = NULL WHERE id = ?').run(dev.device_id);
      }
    }
  }

  // 2) LA 가 없거나 갱신 실패 + 표시할 items 존재 → push-to-start 로 전체 items 로 되살림(배너 동반)
  if (!laHandled && items.length > 0 && dev.push_to_start_token) {
    const result = await sendPushToStartEvent(dev.push_to_start_token, dev.device_token, items, truckConfig);
    if (result.ok) {
      bannerShown = true;
    } else if (result.reason === 'Unregistered') {
      console.warn(`[Push-to-Start] 토큰 무효화 (device ${dev.device_id}, Unregistered)`);
      db.prepare('UPDATE devices SET push_to_start_token = NULL WHERE id = ?').run(dev.device_id);
    } else if (!result.skipped) {
      console.warn(`[Push-to-Start] 되살리기 실패 (device ${dev.device_id}, reason=${result.reason ?? 'unknown'})`);
    }
  }

  // 3) 바뀐 택배의 상태 변경 배너(표준 알림) — 위에서 배너를 안 띄웠고 apns_token 이 있을 때.
  //    LA update 는 무음이라 상태 변경 알림은 이 경로가 담당(LA 미사용 택배 포함).
  if (!bannerShown && dev.apns_token) {
    const changedItem: TrackingItemState = {
      trackingNumber: '',
      status: changedStatus,
      carrierName: dev.changed_carrier,
      itemName: dev.changed_item_name,
      estimatedDelivery: null,
      eventCount: 0,
      statusLabel: dev.changed_label ?? null,
      departureDate: null,
    };
    await sendStatusAlert(dev.device_token, dev.apns_token, changedItem, changedStatus);
  }
}

/**
 * [디버그] 강제 푸시 진단 — 현재 상태로 즉시 표준 배너 + LA update 를 쏘고 APNs 결과 코드를 반환한다.
 * admin 게이팅 라우트에서만 호출. "알림 안 옴" 원인(설정 미비/토픽 불일치/토큰 없음/환경 불일치)을 즉시 판별.
 */
export interface ForcePushDiagnostic {
  trackingId: number;
  found: boolean;
  currentStatus?: string;
  production: boolean;
  alertTopic: string;
  liveActivityTopic: string;
  tokens?: { liveActivityUpdate: boolean; pushToStart: boolean; apnsAlert: boolean };
  alertResult?: ApnsResult;
  liveActivityResult?: ApnsResult;
  hint: string;
}

export async function forcePush(trackingId: number): Promise<ForcePushDiagnostic> {
  const db = getDb();
  const row = db
    .prepare(
      `SELECT t.current_status, t.live_activity_push_token, t.tracking_number, t.carrier_name, t.item_name,
              d.device_token, d.push_to_start_token, d.apns_token,
              (SELECT e.description FROM tracking_events e WHERE e.tracking_id = t.id
                 ORDER BY e.event_time DESC LIMIT 1) AS last_event_description
       FROM trackings t JOIN devices d ON d.id = t.device_id WHERE t.id = ?`,
    )
    .get(trackingId) as
    | {
        current_status: DeliveryStatus;
        live_activity_push_token: string | null;
        tracking_number: string;
        carrier_name: string;
        item_name: string;
        device_token: string;
        push_to_start_token: string | null;
        apns_token: string | null;
        last_event_description: string | null;
      }
    | undefined;

  const base = {
    trackingId,
    production: config.apns.production,
    alertTopic: config.apns.bundleId,
    liveActivityTopic: LIVE_ACTIVITY_TOPIC,
  };
  if (!row) return { ...base, found: false, hint: '해당 trackingId 없음' };

  const status = row.current_status;
  const item: TrackingItemState = {
    trackingNumber: row.tracking_number,
    status,
    carrierName: row.carrier_name,
    itemName: row.item_name,
    estimatedDelivery: null,
    eventCount: 0,
    statusLabel: row.last_event_description ?? null,
    departureDate: null,
  };

  let alertResult: ApnsResult | undefined;
  if (row.apns_token) {
    const now = Math.floor(Date.now() / 1000);
    alertResult = await sendAlertPush({
      deviceToken: row.apns_token,
      payload: {
        aps: {
          alert: { title: item.itemName || item.carrierName, body: item.statusLabel ?? STATUS_DESCRIPTIONS[status] },
          sound: 'default',
        },
      },
      priority: 10,
      expiration: now + 60 * 60,
    });
  }

  let liveActivityResult: ApnsResult | undefined;
  if (row.live_activity_push_token) {
    liveActivityResult = await sendLiveActivityUpdate(
      row.live_activity_push_token,
      [item],
      undefined,
      status === DeliveryStatus.Delivered,
    );
  }

  const tokens = {
    liveActivityUpdate: !!row.live_activity_push_token,
    pushToStart: !!row.push_to_start_token,
    apnsAlert: !!row.apns_token,
  };

  let hint: string;
  const a = alertResult, la = liveActivityResult;
  if (!row.apns_token && !row.live_activity_push_token && !row.push_to_start_token) {
    hint = '토큰이 하나도 없음 → 앱이 토큰 등록을 못함(알림 권한 거부/등록 실패). 기기에서 알림 허용 + 앱 재실행 필요.';
  } else if (a?.skipped || la?.skipped) {
    hint = '서버 APNs 미설정(.p8/APNS_KEY_ID/TEAM_ID) → 모든 푸시 skip. certs/AuthKey.p8 + 환경변수 확인.';
  } else if ((a && a.status === 400 && /Topic/i.test(a.reason ?? '')) || (la && la.status === 400 && /Topic/i.test(la.reason ?? ''))) {
    hint = `BadTopic → 번들ID 불일치. apns-topic=${config.apns.bundleId} 가 앱 번들ID(com.sangjin.Waito)와 대소문자까지 일치해야 함.`;
  } else if (a?.reason === 'BadDeviceToken' || la?.reason === 'BadDeviceToken') {
    hint = 'BadDeviceToken → 샌드박스/운영 APNs 환경 불일치. TestFlight 은 production 토큰 → APNS_PRODUCTION=true 필요.';
  } else if (!row.apns_token) {
    hint = 'apns_token 미등록 → 표준 배너 불가(중간 상태 변경 알림 안 옴). 앱이 PUT /api/devices/apns-token 등록을 못한 상태.';
  } else if (a?.ok || la?.ok) {
    hint = 'APNs 200 OK → 서버→APNs 전달 성공. 기기에 안 뜨면 기기 알림 설정/집중모드(방해금지) 확인.';
  } else {
    hint = `미상 — alert=${JSON.stringify(a)}, liveActivity=${JSON.stringify(la)}`;
  }

  return { ...base, found: true, currentStatus: status, tokens, alertResult, liveActivityResult, hint };
}

/**
 * 표준 원격알림(일반 배너)으로 배송 상태 변경을 알린다. (Live Activity 와 무관, 모든 택배 대상)
 */
async function sendStatusAlert(
  deviceToken: string,
  apnsToken: string,
  item: TrackingItemState,
  status: DeliveryStatus,
): Promise<void> {
  const now = Math.floor(Date.now() / 1000);
  const result = await sendAlertPush({
    deviceToken: apnsToken,
    payload: {
      aps: {
        alert: {
          title: item.itemName || item.carrierName,
          body: item.statusLabel ?? STATUS_DESCRIPTIONS[status],
        },
        sound: 'default',
      },
    },
    priority: 10,
    expiration: now + 60 * 60,  // 오프라인 대비 1시간 보관/재시도
  });

  if (result.reason === 'Unregistered') {
    // 앱 삭제 등 → 해당 디바이스 토큰만 무효화 (토큰 값으로만 매칭하면 같은 토큰을 가진
    // 다른 행까지 지울 수 있어 device 범위로 한정한다)
    getDb()
      .prepare('UPDATE devices SET apns_token = NULL WHERE device_token = ? AND apns_token = ?')
      .run(deviceToken, apnsToken);
  }
}

// ── push-to-start ───────────────────────────────────────────

/**
 * push-to-start 토큰으로 새 Live Activity 를 시작한다. (8시간 한도로 종료된 뒤 재개용)
 * event="start" 페이로드는 alert / attributes-type / attributes 가 필수.
 */
export async function sendPushToStartEvent(
  pushToStartToken: string,
  deviceId: string,
  items: TrackingItemState[],
  truckConfig: Record<string, unknown> | undefined,
): Promise<{ ok: boolean; reason?: string; skipped?: boolean }> {
  const now = Math.floor(Date.now() / 1000);
  const payload = {
    aps: {
      timestamp: now,
      event: 'start',
      'content-state': buildContentState(items, truckConfig),
      // ActivityAttributes 채택 타입명 + 고정 attribute 값 (iOS: struct DeliveryAttributes { deviceId })
      'attributes-type': 'DeliveryAttributes',
      attributes: { deviceId },
      // 다음 8시간 한도까지 신선도 유지
      'stale-date': now + 8 * 60 * 60,
      // 상태 변경을 계기로 되살리므로, 알림 내용도 그 상태로 (의미 있는 알림)
      alert: {
        title: '배송 상태 업데이트',
        body: items[0]?.statusLabel
          ?? (items[0] ? STATUS_DESCRIPTIONS[items[0].status] : '택배 위치를 다시 표시합니다.'),
      },
    },
  };

  const result = await sendLiveActivityPush({
    deviceToken: pushToStartToken,
    payload,
    priority: 10,
    expiration: now + 60 * 60,  // 오프라인 대비 1시간 보관/재시도
  });
  return { ok: result.ok, reason: result.reason, skipped: result.skipped };
}
