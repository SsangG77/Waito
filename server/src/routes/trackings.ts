import { Router, Request, Response } from 'express';
import { getDb } from '../db/database.js';
import { trackPackage, registerWebhook } from '../services/trackerApi.js';
import { resolveNewStatus } from '../services/statusMapper.js';
import { pollTracking } from '../services/pollingService.js';
import { DeliveryStatus, STATUS_T_VALUES, CARRIERS } from '../types/delivery.js';
import { config } from '../config.js';

const router = Router();

// POST /api/trackings — 택배 추적 등록
router.post('/', async (req: Request, res: Response) => {
  const { deviceToken, carrierId, trackingNumber, itemName } = req.body;

  if (!deviceToken || !carrierId || !trackingNumber) {
    res.status(400).json({ error: 'deviceToken, carrierId, trackingNumber are required' });
    return;
  }

  const carrier = CARRIERS.find(c => c.id === carrierId);
  if (!carrier) {
    res.status(400).json({ error: 'Invalid carrierId' });
    return;
  }

  const db = getDb();

  // 디바이스 확인
  const device = db.prepare('SELECT id FROM devices WHERE device_token = ?').get(deviceToken) as { id: number } | undefined;
  if (!device) {
    res.status(404).json({ error: 'Device not registered. Call POST /api/devices/register first' });
    return;
  }

  // 중복 확인
  const existing = db.prepare(
    'SELECT id FROM trackings WHERE device_id = ? AND carrier_id = ? AND tracking_number = ?'
  ).get(device.id, carrierId, trackingNumber);
  if (existing) {
    res.status(409).json({ error: 'Tracking already exists' });
    return;
  }

  // 초기 조회
  let initialStatus = DeliveryStatus.Registered;
  try {
    const result = await trackPackage(carrier.trackerId, trackingNumber);
    if (result.track?.events?.edges) {
      for (const edge of result.track.events.edges) {
        initialStatus = resolveNewStatus(initialStatus, edge.node.status.code, edge.node.description);
      }
    }
  } catch (error) {
    console.warn(`[Tracking] Initial fetch failed, starting as registered:`, error);
  }

  // DB 삽입
  const insertResult = db.prepare(`
    INSERT INTO trackings (device_id, carrier_id, tracking_number, item_name, current_status, current_t_value, carrier_name)
    VALUES (?, ?, ?, ?, ?, ?, ?)
  `).run(
    device.id,
    carrierId,
    trackingNumber,
    itemName || '',
    initialStatus,
    STATUS_T_VALUES[initialStatus],
    carrier.name,
  );

  const trackingId = insertResult.lastInsertRowid as number;

  // Webhook 등록 시도
  try {
    const webhook = await registerWebhook(
      carrier.trackerId,
      trackingNumber,
      `${config.webhookBaseUrl}/webhooks/tracker`,
    );
    db.prepare('UPDATE trackings SET webhook_id = ?, webhook_expires_at = ? WHERE id = ?')
      .run(webhook.webhookId, webhook.expiresAt, trackingId);
  } catch (error) {
    console.warn(`[Tracking] Webhook registration failed, will rely on polling:`, error);
  }

  res.status(201).json({
    id: trackingId,
    carrierId,
    trackingNumber,
    itemName: itemName || '',
    status: initialStatus,
    tValue: STATUS_T_VALUES[initialStatus],
    carrierName: carrier.name,
  });
});

// GET /api/trackings — 내 택배 목록
router.get('/', (req: Request, res: Response) => {
  const { deviceToken } = req.query;

  if (!deviceToken || typeof deviceToken !== 'string') {
    res.status(400).json({ error: 'deviceToken query param is required' });
    return;
  }

  const db = getDb();
  const device = db.prepare('SELECT id FROM devices WHERE device_token = ?').get(deviceToken) as { id: number } | undefined;
  if (!device) {
    res.json([]);
    return;
  }

  const trackings = db.prepare(`
    SELECT id, carrier_id, tracking_number, item_name, current_status, current_t_value,
           carrier_name, estimated_delivery, created_at, delivered_at
    FROM trackings WHERE device_id = ? ORDER BY created_at DESC
  `).all(device.id);

  res.json(trackings);
});

// GET /api/trackings/:id — 상세 조회
router.get('/:id', (req: Request, res: Response) => {
  const db = getDb();
  const tracking = db.prepare('SELECT * FROM trackings WHERE id = ?').get(req.params.id);

  if (!tracking) {
    res.status(404).json({ error: 'Tracking not found' });
    return;
  }

  const events = db.prepare(
    'SELECT * FROM tracking_events WHERE tracking_id = ? ORDER BY event_time ASC'
  ).all(req.params.id);

  res.json({ ...tracking, events });
});

// DELETE /api/trackings/:id — 추적 삭제
router.delete('/:id', (req: Request, res: Response) => {
  const db = getDb();
  const result = db.prepare('DELETE FROM trackings WHERE id = ?').run(req.params.id);

  if (result.changes === 0) {
    res.status(404).json({ error: 'Tracking not found' });
    return;
  }

  res.status(204).send();
});

// POST /api/trackings/:id/refresh — 수동 새로고침
router.post('/:id/refresh', async (req: Request, res: Response) => {
  const trackingId = parseInt(req.params.id, 10);
  if (isNaN(trackingId)) {
    res.status(400).json({ error: 'Invalid tracking ID' });
    return;
  }

  try {
    await pollTracking(trackingId);
    const db = getDb();
    const tracking = db.prepare('SELECT * FROM trackings WHERE id = ?').get(trackingId);
    res.json(tracking);
  } catch (error) {
    res.status(500).json({ error: 'Refresh failed' });
  }
});

// PUT /api/trackings/:id/push-token — Live Activity 푸시토큰 업데이트
router.put('/:id/push-token', (req: Request, res: Response) => {
  const { pushToken } = req.body;

  if (!pushToken || typeof pushToken !== 'string') {
    res.status(400).json({ error: 'pushToken is required' });
    return;
  }

  const db = getDb();
  const result = db.prepare(
    "UPDATE trackings SET live_activity_push_token = ?, updated_at = datetime('now') WHERE id = ?"
  ).run(pushToken, req.params.id);

  if (result.changes === 0) {
    res.status(404).json({ error: 'Tracking not found' });
    return;
  }

  res.json({ success: true });
});

export default router;
