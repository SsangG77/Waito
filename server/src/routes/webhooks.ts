import { Router, Request, Response } from 'express';
import { getDb } from '../db/database.js';
import { trackPackage } from '../services/trackerApi.js';
import { resolveNewStatus } from '../services/statusMapper.js';
import { pushTrackingUpdate } from '../services/pushService.js';
import { DeliveryStatus, STATUS_T_VALUES } from '../types/delivery.js';

const router = Router();

// POST /webhooks/tracker — tracker.delivery 콜백
// Webhook 1초 응답 제한: 즉시 202 응답 후 비동기 처리
router.post('/tracker', (req: Request, res: Response) => {
  // 즉시 202 응답
  res.status(202).json({ ok: true });

  // 비동기 처리
  processWebhook(req.body).catch(error => {
    console.error('[Webhook] Processing error:', error);
  });
});

async function processWebhook(payload: any): Promise<void> {
  // 최신 콜백 payload 는 { carrierId, trackingNumber } 만 전달된다.
  // 상태 정보가 없으므로 track API 로 최신 이벤트를 다시 조회한다.
  const { trackingNumber, carrierId } = payload;

  if (!trackingNumber || !carrierId) {
    console.warn('[Webhook] Invalid payload:', payload);
    return;
  }

  let result;
  try {
    // payload.carrierId 는 tracker.delivery 식별자(예: kr.coupangls)이므로 그대로 사용
    result = await trackPackage(carrierId, trackingNumber);
  } catch (error) {
    console.error(`[Webhook] track fetch failed for ${trackingNumber}:`, error);
    return;
  }

  if (!result.track?.lastEvent) return;

  const db = getDb();

  const trackings = db.prepare(`
    SELECT t.id, t.current_status
    FROM trackings t
    WHERE t.tracking_number = ? AND t.delivered_at IS NULL
  `).all(trackingNumber) as Array<{
    id: number;
    current_status: DeliveryStatus;
  }>;

  if (trackings.length === 0) {
    console.warn(`[Webhook] No active tracking found for ${trackingNumber}`);
    return;
  }

  for (const tracking of trackings) {
    let newStatus = tracking.current_status;

    for (const edge of result.track.events.edges) {
      const event = edge.node;
      newStatus = resolveNewStatus(newStatus, event.status.code, event.description);

      // 이벤트 기록
      db.prepare(`
        INSERT OR IGNORE INTO tracking_events (tracking_id, tracker_status, mapped_status, description, event_time, location)
        VALUES (?, ?, ?, ?, ?, ?)
      `).run(
        tracking.id,
        event.status.code,
        newStatus,
        event.description,
        event.time,
        event.location || null,
      );
    }

    if (newStatus !== tracking.current_status) {
      db.prepare(`
        UPDATE trackings
        SET current_status = ?, current_t_value = ?, updated_at = datetime('now'),
            last_event_time = ?,
            delivered_at = CASE WHEN ? = 'delivered' THEN datetime('now') ELSE delivered_at END
        WHERE id = ?
      `).run(
        newStatus,
        STATUS_T_VALUES[newStatus],
        result.track.lastEvent.time,
        newStatus,
        tracking.id,
      );

      await pushTrackingUpdate(tracking.id, newStatus);
    }
  }
}

export default router;
