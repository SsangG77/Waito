import cron from 'node-cron';
import { getDb } from '../db/database.js';
import { trackPackage, registerWebhook } from './trackerApi.js';
import { resolveNewStatus } from './statusMapper.js';
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
    'SELECT id, carrier_id, tracking_number, current_status FROM trackings WHERE id = ?'
  ).get(trackingId) as {
    id: number;
    carrier_id: string;
    tracking_number: string;
    current_status: DeliveryStatus;
  } | undefined;

  if (!tracking) return;

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

      await pushTrackingUpdate(trackingId, newStatus);
    }

    // 폴링 시간 업데이트
    db.prepare("UPDATE trackings SET last_polled_at = datetime('now') WHERE id = ?").run(trackingId);
  } catch (error) {
    console.error(`[Polling] Failed for tracking ${trackingId}:`, error);
  }
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
      WHERE current_status IN ('outForDelivery', 'delivering')
        AND delivered_at IS NULL
    `).all() as Array<{ id: number }>;

    for (const t of trackings) {
      await pollTracking(t.id);
    }
  });

  // Webhook 갱신 (매일 자정)
  cron.schedule('0 0 * * *', async () => {
    console.log('[Webhook] Renewing expiring webhooks...');
    const db = getDb();
    const trackings = db.prepare(`
      SELECT id, carrier_id, tracking_number, webhook_id FROM trackings
      WHERE webhook_id IS NOT NULL
        AND delivered_at IS NULL
        AND webhook_expires_at < datetime('now', '+24 hours')
    `).all() as Array<{
      id: number;
      carrier_id: string;
      tracking_number: string;
      webhook_id: string;
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
          UPDATE trackings SET webhook_id = ?, webhook_expires_at = ?, updated_at = datetime('now')
          WHERE id = ?
        `).run(result.webhookId, result.expiresAt, t.id);
      } catch (error) {
        console.error(`[Webhook] Renewal failed for tracking ${t.id}:`, error);
      }
    }
  });

  console.log('[Polling] Scheduler started');
}

export { pollTracking };
