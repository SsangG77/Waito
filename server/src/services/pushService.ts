import { DeliveryStatus } from '../types/delivery.js';
import { getDb } from '../db/database.js';
import { sendLiveActivityPush, sendAlertPush } from './apnsClient.js';

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
): Promise<{ ok: boolean; reason?: string; skipped?: boolean }> {
  const now = Math.floor(Date.now() / 1000);
  const aps: Record<string, unknown> = {
    timestamp: now,
    event: isEnd ? 'end' : 'update',
    'content-state': buildContentState(items, truckConfig),
  };

  if (isEnd) {
    // 배송 완료를 사용자가 인지하도록 배너 알림을 띄우고, 최종 상태를 1시간 보여준 뒤 정리
    aps.alert = {
      title: '배송 완료',
      body: items[0]?.statusLabel
        ?? (items[0] ? STATUS_DESCRIPTIONS[items[0].status] : STATUS_DESCRIPTIONS[DeliveryStatus.Delivered]),
    };
    aps['dismissal-date'] = now + 60 * 60;
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
  return { ok: result.ok, reason: result.reason, skipped: result.skipped };
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
export async function pushTrackingUpdate(trackingId: number, status: DeliveryStatus): Promise<void> {
  const db = getDb();
  const row = db
    .prepare(
      `SELECT t.live_activity_push_token, t.live_activity_started_at,
              t.tracking_number, t.carrier_name, t.item_name, t.estimated_delivery, t.created_at,
              d.device_token, d.push_to_start_token, d.truck_config, d.apns_token,
              (SELECT COUNT(*) FROM tracking_events e WHERE e.tracking_id = t.id) AS event_count,
              (SELECT e.description FROM tracking_events e WHERE e.tracking_id = t.id
                 ORDER BY e.event_time DESC LIMIT 1) AS last_event_description
       FROM trackings t JOIN devices d ON d.id = t.device_id
       WHERE t.id = ?`,
    )
    .get(trackingId) as
    | {
        live_activity_push_token: string | null;
        live_activity_started_at: string | null;
        tracking_number: string;
        carrier_name: string;
        item_name: string;
        estimated_delivery: string | null;
        created_at: string | null;
        device_token: string;
        push_to_start_token: string | null;
        truck_config: string | null;
        apns_token: string | null;
        event_count: number;
        last_event_description: string | null;
      }
    | undefined;

  if (!row) return;

  const item: TrackingItemState = {
    trackingNumber: row.tracking_number,
    status,
    carrierName: row.carrier_name,
    itemName: row.item_name,
    estimatedDelivery: row.estimated_delivery,
    eventCount: row.event_count ?? 0,
    statusLabel: row.last_event_description ?? null,
    departureDate: row.created_at ?? null,
  };
  const truckConfig = safeParseJson(row.truck_config);
  const isEnd = status === DeliveryStatus.Delivered;

  // Activity 가 아직 살아있을 것으로 보이는지 (시작 후 8시간 미만)
  const startedAt = parseSqliteUtc(row.live_activity_started_at);
  const aliveByTime = startedAt > 0 && Date.now() - startedAt < ACTIVITY_MAX_MS;

  // Live Activity 경로가 이미 배너를 띄웠는지(=중복 알림 방지용). end / push-to-start 는 배너 동반.
  let bannerShown = false;
  // update 가 처리(성공/설정미비)되어 push-to-start 폴백이 불필요한지
  let laHandled = false;

  // 1) 살아있으면 update 로 화면 갱신 (중간 상태는 무음, end 는 배너)
  if (row.live_activity_push_token && aliveByTime) {
    const result = await sendLiveActivityUpdate(row.live_activity_push_token, [item], truckConfig, isEnd);
    if (result.ok) {
      bannerShown = isEnd;   // end 만 배너, 중간 update 는 무음
      laHandled = true;
    } else if (result.skipped) {
      laHandled = true;      // APNs 설정 미비 — 폴백도 어차피 skip
    } else {
      if (result.reason === 'Unregistered') {
        db.prepare('UPDATE trackings SET live_activity_push_token = NULL WHERE id = ?').run(trackingId);
      }
      // update 실패(만료 등) → 아래 push-to-start 폴백으로 진행
    }
  }

  // 2) Activity 가 죽었거나 update 실패 → 이번 상태 변경을 계기로 push-to-start 로 되살림 (배너 동반)
  if (!laHandled && !isEnd && row.push_to_start_token) {
    const result = await sendPushToStartEvent(row.push_to_start_token, row.device_token, [item], truckConfig);
    if (result.ok) {
      bannerShown = true;
      db.prepare("UPDATE trackings SET live_activity_started_at = datetime('now') WHERE id = ?").run(trackingId);
    } else if (result.reason === 'Unregistered') {
      console.warn(`[Push-to-Start] 토큰 무효화 (tracking ${trackingId}, Unregistered)`);
      db.prepare('UPDATE devices SET push_to_start_token = NULL WHERE device_token = ?').run(row.device_token);
    } else if (!result.skipped) {
      console.warn(`[Push-to-Start] 되살리기 실패 (tracking ${trackingId}, reason=${result.reason ?? 'unknown'})`);
    }
  }

  // 3) 모든 상태 변경 → 일반 알림(배너). 단 위에서 이미 배너를 띄웠으면 중복 방지로 생략.
  //    Live Activity 미사용 택배도 이 경로로 알림을 받는다.
  if (!bannerShown && row.apns_token) {
    await sendStatusAlert(row.device_token, row.apns_token, item, status);
  }
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
