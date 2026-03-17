import { Router, Request, Response } from 'express';
import { getDb } from '../db/database.js';
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
  const { trackingNumber, carrierId, events } = payload;

  if (!trackingNumber || !events?.length) {
    console.warn('[Webhook] Invalid payload:', payload);
    return;
  }

  const db = getDb();

  // carrier trackerId → waito carrierId 매핑
  const trackings = db.prepare(`
    SELECT t.id, t.current_status, t.carrier_id
    FROM trackings t
    WHERE t.tracking_number = ? AND t.delivered_at IS NULL
  `).all(trackingNumber) as Array<{
    id: number;
    current_status: DeliveryStatus;
    carrier_id: string;
  }>;

  if (trackings.length === 0) {
    console.warn(`[Webhook] No active tracking found for ${trackingNumber}`);
    return;
  }

  for (const tracking of trackings) {
    let newStatus = tracking.current_status;

    for (const event of events) {
      const statusCode = event.status?.code || event.statusCode;
      const description = event.description || '';

      newStatus = resolveNewStatus(newStatus, statusCode, description);

      // 이벤트 기록
      db.prepare(`
        INSERT OR IGNORE INTO tracking_events (tracking_id, tracker_status, mapped_status, description, event_time, location)
        VALUES (?, ?, ?, ?, ?, ?)
      `).run(
        tracking.id,
        statusCode,
        newStatus,
        description,
        event.time || new Date().toISOString(),
        event.location || null,
      );
    }

    if (newStatus !== tracking.current_status) {
      db.prepare(`
        UPDATE trackings
        SET current_status = ?, current_t_value = ?, updated_at = datetime('now'),
            last_event_time = datetime('now'),
            delivered_at = CASE WHEN ? = 'delivered' THEN datetime('now') ELSE delivered_at END
        WHERE id = ?
      `).run(
        newStatus,
        STATUS_T_VALUES[newStatus],
        newStatus,
        tracking.id,
      );

      await pushTrackingUpdate(tracking.id, newStatus);
    }
  }
}

export default router;
