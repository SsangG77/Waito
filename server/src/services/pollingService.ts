import cron from 'node-cron';
import { getDb } from '../db/database.js';
import { trackPackage, registerWebhook, TEST_TRACKING_NUMBER, TEST_STEPS, TEST_STEP_INTERVAL_MS, testStepIndex } from './trackerApi.js';
import { resolveNewStatus, mapTrackerStatus } from './statusMapper.js';
import { pushTrackingUpdate } from './pushService.js';
import { isCredentialExpired } from './credentialMonitor.js';
import { DeliveryStatus, STATUS_T_VALUES, CARRIERS } from '../types/delivery.js';
import { config } from '../config.js';

/**
 * 단일 추적 건을 폴링하여 상태를 업데이트한다.
 */
async function pollTracking(trackingId: number): Promise<void> {
  const db = getDb();
  const tracking = db.prepare(
    'SELECT id, carrier_id, tracking_number, current_status, created_at FROM trackings WHERE id = ?'
  ).get(trackingId) as {
    id: number;
    carrier_id: string;
    tracking_number: string;
    current_status: DeliveryStatus;
    created_at: string;
  } | undefined;

  if (!tracking) return;

  // 테스트 운송장은 시간 기반 순환(전진 제약/delivered_at 없이)으로 별도 처리
  if (tracking.tracking_number === TEST_TRACKING_NUMBER) {
    await pollTestTracking(tracking);
    return;
  }

  const carrier = CARRIERS.find(c => c.id === tracking.carrier_id);
  if (!carrier) return;

  if (isCredentialExpired()) {
    console.warn(`[Polling] Skipping tracking ${trackingId} — credential expired`);
    return;
  }

  try {
    const result = await trackPackage(carrier.trackerId, tracking.tracking_number);

    if (!result.track?.lastEvent) return;

    // 모든 이벤트를 순서대로 처리
    let newStatus = tracking.current_status;
    for (const edge of result.track.events.edges) {
      const event = edge.node;
      newStatus = resolveNewStatus(newStatus, event.status.code, event.description);

      // 이벤트 기록
      db.prepare(`
        INSERT OR IGNORE INTO tracking_events (tracking_id, tracker_status, mapped_status, description, event_time, location)
        VALUES (?, ?, ?, ?, ?, ?)
      `).run(
        trackingId,
        event.status.code,
        newStatus,
        event.description,
        event.time,
        event.location || null,
      );
    }

    // 상태가 변경된 경우에만 업데이트
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
 * 배송 전 택배: 2시간마다, 배송출발 이후: 30분마다 폴링
 */
export function startPollingScheduler(): void {
  // 배송 전 (2시간마다)
  cron.schedule('0 */2 * * *', async () => {
    console.log('[Polling] Running pre-delivery poll...');
    const db = getDb();
    const trackings = db.prepare(`
      SELECT id FROM trackings
      WHERE current_status IN ('registered', 'pickedUp', 'inTransitIn', 'inTransitOut')
        AND delivered_at IS NULL
    `).all() as Array<{ id: number }>;

    for (const t of trackings) {
      await pollTracking(t.id);
    }
  });

  // 배송출발 이후 (30분마다)
  cron.schedule('*/30 * * * *', async () => {
    console.log('[Polling] Running active delivery poll...');
    const db = getDb();
    const trackings = db.prepare(`
      SELECT id FROM trackings
      WHERE (current_status IN ('outForDelivery', 'delivering') AND delivered_at IS NULL)
         OR (tracking_number = ? AND delivered_at IS NULL)
    `).all(TEST_TRACKING_NUMBER) as Array<{ id: number }>;

    for (const t of trackings) {
      await pollTracking(t.id);
    }
  });

  // Webhook 갱신 (매일 자정)
  cron.schedule('0 0 * * *', async () => {
    console.log('[Webhook] Renewing expiring webhooks...');
    const db = getDb();
    const trackings = db.prepare(`
      SELECT id, carrier_id, tracking_number FROM trackings
      WHERE webhook_expires_at IS NOT NULL
        AND delivered_at IS NULL
        AND webhook_expires_at < datetime('now', '+24 hours')
    `).all() as Array<{
      id: number;
      carrier_id: string;
      tracking_number: string;
    }>;

    for (const t of trackings) {
      try {
        const carrier = CARRIERS.find(c => c.id === t.carrier_id);
        if (!carrier) continue;

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
