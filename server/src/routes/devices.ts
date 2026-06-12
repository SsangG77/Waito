import { Router, Request, Response } from 'express';
import { getDb } from '../db/database.js';

const router = Router();

// POST /api/devices/register
router.post('/register', (req: Request, res: Response) => {
  const { deviceToken } = req.body;

  if (!deviceToken || typeof deviceToken !== 'string') {
    res.status(400).json({ error: 'deviceToken is required' });
    return;
  }

  const db = getDb();

  const existing = db.prepare('SELECT id FROM devices WHERE device_token = ?').get(deviceToken) as { id: number } | undefined;

  if (existing) {
    db.prepare("UPDATE devices SET updated_at = datetime('now') WHERE id = ?").run(existing.id);
    res.json({ deviceId: existing.id });
    return;
  }

  const result = db.prepare('INSERT INTO devices (device_token) VALUES (?)').run(deviceToken);
  res.status(201).json({ deviceId: result.lastInsertRowid });
});

// PUT /api/devices/push-to-start-token — push-to-start 토큰 + 트럭 설정 등록
// (디바이스/앱당 1개. 8시간 한도로 종료된 Live Activity 를 서버가 재시작할 때 사용)
router.put('/push-to-start-token', (req: Request, res: Response) => {
  const { deviceToken, pushToStartToken, truckConfig } = req.body;

  if (!deviceToken || typeof deviceToken !== 'string' || !pushToStartToken || typeof pushToStartToken !== 'string') {
    res.status(400).json({ error: 'deviceToken, pushToStartToken are required' });
    return;
  }

  const db = getDb();
  const device = db.prepare('SELECT id FROM devices WHERE device_token = ?').get(deviceToken) as
    | { id: number }
    | undefined;
  if (!device) {
    res.status(404).json({ error: 'Device not registered. Call POST /api/devices/register first' });
    return;
  }

  // truckConfig 가 없으면 기존 값 유지(COALESCE)
  const truckConfigJson = truckConfig ? JSON.stringify(truckConfig) : null;
  db.prepare(
    `UPDATE devices
     SET push_to_start_token = ?, truck_config = COALESCE(?, truck_config), updated_at = datetime('now')
     WHERE id = ?`,
  ).run(pushToStartToken, truckConfigJson, device.id);

  res.json({ success: true });
});

export default router;
