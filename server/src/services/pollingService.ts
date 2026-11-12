import cron from 'node-cron';
import { getDb } from '../db/database.js';
import { trackPackage, registerWebhook, isTrackingNotFoundError, isInvalidTrackingNumberError, TEST_TRACKING_NUMBER, TEST_STEPS, TEST_STEP_INTERVAL_MS, testStepIndex } from './trackerApi.js';
import { detectCarrier } from './carrierDetect.js';
import { trackPackage17, isTrack17Configured } from './track17Api.js';
import { resolveNewStatus, mapTrackerStatus } from './statusMapper.js';
import { pushTrackingUpdate, reviveExpiredActivities } from './pushService.js';
import { isCredentialExpired } from './credentialMonitor.js';
import { DeliveryStatus, STATUS_T_VALUES, CARRIERS } from '../types/delivery.js';
import { config } from '../config.js';

/**
 * 한 번도 조회된 적 없는 번호(NOT_FOUND 계속)를 5분 조회에서 빼는 기준 시간.
 * ponytail: 운영 DB 근거 숫자 확인 전 임시값 — 결국 조회된 번호의 "등록→첫 조회" 최대치보다 넉넉히 다시 정할 것.
 */
export const NOT_FOUND_STOP_HOURS = 72;

/** 등록 후 기준 시간이 지났는데 한 번도 조회 안 된 번호인지. created_at 은 SQLite UTC 'YYYY-MM-DD HH:MM:SS'. */
export function isNotFoundTooLong(createdAt: string, lastEventTime: string | null, nowMs = Date.now()): boolean {
  if (lastEventTime) return false;
  const createdMs = new Date(createdAt.replace(' ', 'T') + 'Z').getTime();
  return nowMs - createdMs >= NOT_FOUND_STOP_HOURS * 60 * 60 * 1000;
}

/**
 * 5분 조회를 멈추고, 번호당 1번만 모든 택배사에 다시 조회한다.
 * 다른 택배사에서 찾아도 택배사를 바꾸지 않는다 — suggested_carrier_id 에만 남기고 앱이 사용자에게 묻는다.
 * (국내 운송장은 자릿수가 겹쳐 다른 택배사에서 남의 택배가 잡힐 수 있음)
 */
async function stopAndRedetect(
  tracking: { id: number; carrier_id: string; tracking_number: string },
  reason: string,
): Promise<void> {
  const db = getDb();
  db.prepare("UPDATE trackings SET polling_stopped_at = COALESCE(polling_stopped_at, datetime('now')) WHERE id = ?")
    .run(tracking.id);

  // 먼저 "했음"을 남겨 동시에 들어온 조회(앱 열기 + 5분 조회)가 두 번 다시 찾지 않게 한다.
  const claimed = db.prepare(
    "UPDATE trackings SET redetect_done_at = datetime('now') WHERE id = ? AND redetect_done_at IS NULL",
  ).run(tracking.id).changes > 0;
  if (!claimed) return;

  console.log(`[Poll] tracking=${tracking.id} 5분 조회 멈춤 (${reason}) → 모든 택배사 다시 조회`);
  const found = await detectCarrier(tracking.tracking_number);
  if (!found) {
    console.log(`[Poll] tracking=${tracking.id} 다시 조회: 어느 택배사에서도 못 찾음`);
    return;
  }
  if (found.id === tracking.carrier_id) {
    // 원래 택배사에서 이제 조회됨 → 정상 조회 대상으로 복귀
    db.prepare('UPDATE trackings SET polling_stopped_at = NULL WHERE id = ?').run(tracking.id);
    return;
  }
  console.log(`[Poll] tracking=${tracking.id} 다시 조회: ${found.id} 에서 찾음 (사용자 선택 대기)`);
  db.prepare('UPDATE trackings SET suggested_carrier_id = ? WHERE id = ?').run(found.id, tracking.id);
}

/**
 * 단일 추적 건을 폴링하여 상태를 업데이트한다.
 */
async function pollTracking(trackingId: number): Promise<void> {
  const db = getDb();
  const tracking = db.prepare(
    'SELECT id, carrier_id, tracking_number, current_status, created_at, last_event_time FROM trackings WHERE id = ?'
  ).get(trackingId) as {
    id: number;
    carrier_id: string;
    tracking_number: string;
    current_status: DeliveryStatus;
    created_at: string;
    last_event_time: string | null;
  } | undefined;

  if (!tracking) return;

  // 테스트 운송장은 시간 기반 순환(전진 제약/delivered_at 없이)으로 별도 처리
  if (tracking.tracking_number === TEST_TRACKING_NUMBER) {
    await pollTestTracking(tracking);
    return;
  }

  const carrier = CARRIERS.find(c => c.id === tracking.carrier_id);
  if (!carrier) return;

  const isTrack17 = carrier.provider === 'track17';

  // 제공자별 사용 불가 조건 — 해당 제공자 쪽만 건너뛴다.
  if (isTrack17) {
    if (!isTrack17Configured()) {
      console.warn(`[Polling] Skipping tracking ${trackingId} — 17TRACK key not configured`);
      return;
    }
  } else if (isCredentialExpired()) {
    console.warn(`[Polling] Skipping tracking ${trackingId} — credential expired`);
    return;
  }

  try {
    const result = isTrack17
      ? await trackPackage17(carrier.trackerId, tracking.tracking_number)
      : await trackPackage(carrier.trackerId, tracking.tracking_number);

    // 조회 결과를 매번 한 줄로 남긴다 — 성공한 조회의 내용이 없으면
    // "택배사 앱과 다르다" 신고 때 당시 무엇을 받았는지 거꾸로 볼 수 없다.
    const edges = result.track?.events?.edges ?? [];
    const last = edges[edges.length - 1]?.node;
    console.log(
      `[Poll] tracking=${trackingId} carrier=${carrier.trackerId} events=${edges.length}` +
      (last ? ` last="${last.description}" at=${last.time} code=${last.status.code}` : ' last=none'),
    );

    if (!result.track?.lastEvent) {
      // 17TRACK 은 못 찾으면 오류 대신 빈 결과를 준다 — tracker 의 NOT_FOUND 와 같게 취급
      if (isNotFoundTooLong(tracking.created_at, tracking.last_event_time)) {
        await stopAndRedetect(tracking, `${NOT_FOUND_STOP_HOURS}시간째 조회 결과 없음`);
      }
      return;
    }

    // 모든 이벤트를 순서대로 처리
    let newStatus = tracking.current_status;
    for (const edge of result.track.events.edges) {
      const event = edge.node;
      newStatus = resolveNewStatus(newStatus, event.status.code, event.description, carrier.provider);

      // 이벤트 기록
      db.prepare(`
        INSERT OR IGNORE INTO tracking_events (tracking_id, tracker_status, mapped_status, description, event_time, location, lat, lon)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      `).run(
        trackingId,
        event.status.code,
        newStatus,
        event.description,
        event.time,
        event.location?.name || null,
        event.location?.lat ?? null,
        event.location?.lon ?? null,
      );

      // 좌표 없이 저장돼 있던 기존 이벤트를 뒤늦게 채운다.
      // (중복 방지 INSERT OR IGNORE 는 기존 행을 건드리지 않아 좌표가 영영 비게 됨)
      if (event.location?.lat != null && event.location?.lon != null) {
        db.prepare(`
          UPDATE tracking_events SET lat = ?, lon = ?
          WHERE tracking_id = ? AND event_time = ? AND description = ? AND lat IS NULL
        `).run(event.location.lat, event.location.lon, trackingId, event.time, event.description);
      }
    }

    // 상태가 그대로여도 최신 이벤트 시각은 항상 반영한다.
    // 간선 허브를 여러 번 거치면 상태는 inTransitIn 로 동일하지만 이벤트는 계속 쌓이는데,
    // 이걸 상태 변경 시에만 갱신하면 last_event_time 이 며칠씩 멈춰
    // 정렬(최근 업데이트순)·"확인 중" 판정이 실제와 어긋난다.
    // sub_stage(통관 등)는 COALESCE — 한 번 설정되면 유지(이벤트 50개 제한으로 잘려도 뒤로 안 감).
    db.prepare(`
      UPDATE trackings SET last_event_time = ?, sub_stage = COALESCE(?, sub_stage),
                           polling_stopped_at = NULL, updated_at = datetime('now') WHERE id = ?
    `).run(result.track.lastEvent.time, result.track.subStage ?? null, trackingId);

    // 상태가 변경된 경우에만 단계·푸시 갱신
    if (newStatus !== tracking.current_status) {
      db.prepare(`
        UPDATE trackings
        SET current_status = ?, current_t_value = ?, last_event_time = ?, updated_at = datetime('now'),
            delivered_at = CASE WHEN ? = 'delivered' THEN datetime('now') ELSE delivered_at END
        WHERE id = ?
      `).run(
        newStatus,
        STATUS_T_VALUES[newStatus],
        result.track.lastEvent.time,
        newStatus,
        trackingId,
      );

      // 배송완료로 "전환되는 순간"에만 해당 디바이스의 누적 완료 카운트 +1
      // (old != new 이고 new == delivered 이므로 항상 진짜 전환 = 중복 카운트 없음)
      if (newStatus === DeliveryStatus.Delivered) {
        db.prepare(`
          UPDATE devices SET delivered_count = delivered_count + 1
          WHERE id = (SELECT device_id FROM trackings WHERE id = ?)
        `).run(trackingId);
      }

      await pushTrackingUpdate(trackingId, newStatus);
    }

    // 폴링 시간 업데이트
    db.prepare("UPDATE trackings SET last_polled_at = datetime('now') WHERE id = ?").run(trackingId);
  } catch (error) {
    console.error(`[Polling] Failed for tracking ${trackingId}:`, error);
    if (isInvalidTrackingNumberError(error)) {
      await stopAndRedetect(tracking, '자릿수 오류');
    } else if (isTrackingNotFoundError(error) && isNotFoundTooLong(tracking.created_at, tracking.last_event_time)) {
      await stopAndRedetect(tracking, `${NOT_FOUND_STOP_HOURS}시간째 조회 결과 없음`);
    }
  }
}

/**
 * 테스트 운송장(test970719) 전용 폴링 — created_at 기준 TEST_STEP_INTERVAL_MS(1시간)마다 단계 전진, 배송완료에서 멈춤.
 * 일반 폴링과 달리 전진 제약(resolveNewStatus)·delivered_at 설정을 하지 않아 뒤로(접수) 돌아갈 수 있다.
 */
async function pollTestTracking(tracking: {
  id: number;
  tracking_number: string;
  current_status: DeliveryStatus;
  created_at: string;
}): Promise<void> {
  const db = getDb();

  // 앱에 실제 등록된(활성) 디바이스에만 테스트 폴링·푸시.
  // 앱에서 지웠는데 다른 구설치/desync 디바이스에 남은 test970719 행이 계속 푸시하던 문제 방지.
  // apns_token 은 최신 설치에만 유지되므로(등록 시 타 디바이스 토큰 NULL) 활성 여부의 기준으로 쓴다.
  const activeDevice = db.prepare(
    `SELECT 1 FROM devices d JOIN trackings t ON t.device_id = d.id
     WHERE t.id = ? AND d.apns_token IS NOT NULL`,
  ).get(tracking.id);
  if (!activeDevice) {
    db.prepare("UPDATE trackings SET last_polled_at = datetime('now') WHERE id = ?").run(tracking.id);
    return;
  }

  // SQLite datetime('now') 은 'YYYY-MM-DD HH:MM:SS'(UTC) → ISO 로 변환해 파싱
  const createdAtMs = new Date(tracking.created_at.replace(' ', 'T') + 'Z').getTime();
  const step = testStepIndex(createdAtMs);

  // 테스트 택배는 매 폴링마다 이벤트를 현재 사이클(0..step)로 재구성한다.
  // 배송완료 후 다음 사이클(접수)로 순환할 때 이전 사이클 이벤트가 남으면 타임라인이 무한 누적되므로,
  // 전체 삭제 후 현재 단계까지만 다시 삽입(= 사이클마다 초기화). 트랜잭션으로 원자적 처리.
  const rebuildEvents = db.transaction(() => {
    db.prepare('DELETE FROM tracking_events WHERE tracking_id = ?').run(tracking.id);
    const insert = db.prepare(`
      INSERT INTO tracking_events (tracking_id, tracker_status, mapped_status, description, event_time, location)
      VALUES (?, ?, ?, ?, ?, ?)
    `);
    for (let i = 0; i <= step; i++) {
      const s = TEST_STEPS[i];
      const mapped = mapTrackerStatus(s.code, s.description) ?? DeliveryStatus.Registered;
      insert.run(
        tracking.id,
        s.code,
        mapped,
        s.description,
        new Date(createdAtMs + i * TEST_STEP_INTERVAL_MS).toISOString(),
        s.location,
      );
    }
  });
  rebuildEvents();

  const cur = TEST_STEPS[step];
  const newStatus = mapTrackerStatus(cur.code, cur.description) ?? DeliveryStatus.Registered;

  if (newStatus !== tracking.current_status) {
    db.prepare(`
      UPDATE trackings
      SET current_status = ?, current_t_value = ?, last_event_time = ?, updated_at = datetime('now')
      WHERE id = ?
    `).run(
      newStatus,
      STATUS_T_VALUES[newStatus],
      new Date(createdAtMs + step * TEST_STEP_INTERVAL_MS).toISOString(),
      tracking.id,
    );
    await pushTrackingUpdate(tracking.id, newStatus);
  }

  // 배송완료면 delivered_at 설정 → 순환 없이 완료에서 멈추고 이후 폴링·푸시 제외(재등록 전까지).
  if (newStatus === DeliveryStatus.Delivered) {
    db.prepare("UPDATE trackings SET delivered_at = COALESCE(delivered_at, datetime('now')) WHERE id = ?")
      .run(tracking.id);
  }

  db.prepare("UPDATE trackings SET last_polled_at = datetime('now') WHERE id = ?").run(tracking.id);
}

/**
 * 미완료 택배 전체를 5분마다 폴링.
 *
 * webhook 이 주 경로이고 폴링은 백업이지만, webhook 이 죽으면 이 주기가 곧 지연 상한이 된다.
 * tracker.delivery 월 쿼터는 "고유 운송장 번호 수"(10,000) 기준이라 같은 운송장을 자주 조회해도
 * 월 사용량이 늘지 않는다. 제약은 APICallsPerSecond(10) 뿐 → 직렬 호출인 현재 구조에선 여유.
 * (단계별로 주기를 나눴던 이전 구조는 주기가 같아져 의미가 없어 하나로 합침)
 */
export function startPollingScheduler(): void {
  cron.schedule('*/5 * * * *', async () => {
    console.log('[Polling] Running poll...');
    const db = getDb();
    const trackings = db.prepare(`
      SELECT id FROM trackings
      WHERE delivered_at IS NULL
        AND polling_stopped_at IS NULL  -- 조회 안 되는 번호는 앱을 열 때만 조회(GET /api/trackings)
    `).all() as Array<{ id: number }>;

    for (const t of trackings) {
      await pollTracking(t.id);
    }
  });

  // Live Activity keep-alive (30분마다) — 8시간 한도로 사라진 LA 를 push-to-start 로 되살린다.
  // 해외 배송처럼 상태가 며칠 안 바뀌는 경우에도 DI/잠금화면 표시가 유지되게 한다.
  // (심야 억제·대상 판정은 reviveExpiredActivities 내부에서 처리)
  cron.schedule('*/30 * * * *', async () => {
    try {
      await reviveExpiredActivities();
    } catch (error) {
      console.error('[Keep-Alive] 실행 실패:', error);
    }
  });

  // Webhook 갱신 (매일 자정)
  cron.schedule('0 0 * * *', async () => {
    console.log('[Webhook] Renewing expiring webhooks...');
    const db = getDb();
    const trackings = db.prepare(`
      SELECT id, carrier_id, tracking_number FROM trackings
      WHERE delivered_at IS NULL
        AND (
          -- 최초 등록이 실패해 NULL 로 남은 건도 매일 재시도한다.
          -- (IS NOT NULL 조건만 두면 그 택배는 평생 webhook 없이 폴링에만 의존)
          webhook_expires_at IS NULL
          OR webhook_expires_at < datetime('now', '+24 hours')
        )
    `).all() as Array<{
      id: number;
      carrier_id: string;
      tracking_number: string;
    }>;

    for (const t of trackings) {
      try {
        const carrier = CARRIERS.find(c => c.id === t.carrier_id);
        if (!carrier) continue;
        // 17TRACK 은 운송장별 webhook 등록이 없다 — 넣으면 tracker.delivery 에 헛요청만 간다.
        if (carrier.provider !== 'tracker') continue;

        const result = await registerWebhook(
          carrier.trackerId,
          t.tracking_number,
          `${config.webhookBaseUrl}/webhooks/tracker`,
        );

        db.prepare(`
          UPDATE trackings SET webhook_expires_at = ?, updated_at = datetime('now')
          WHERE id = ?
        `).run(result.expiresAt, t.id);
      } catch (error) {
        console.error(`[Webhook] Renewal failed for tracking ${t.id}:`, error);
      }
    }
  });

  // Push-to-Start 재개는 별도 8시간 타이머가 아니라, 배송 상태 변경 시(pushTrackingUpdate)
  // Activity 가 죽어 있으면 그 순간 되살리는 이벤트 기반으로 처리한다. (의미 없는 재시작 알림 방지)

  console.log('[Polling] Scheduler started');
}


export { pollTracking };
