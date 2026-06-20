import { Router, Request, Response } from 'express';
import { getDb } from '../db/database.js';

const router = Router();

// 포인트 경제 — 배송완료 1건 = 1포인트, 부품 1개 해제 = 3포인트.
// 포인트로 해제 가능한 계열(에셋명 2번째 토큰). 그 외(탱크·기차·물탱크·건설·컨테이너)는 Plus 전용.
const POINT_UNLOCK_COST = 3;
const POINT_UNLOCKABLE_FAMILIES = new Set(['TruckHead', 'Truck', 'Wheels']);

function familyToken(part: string): string {
  const parts = part.split('_');
  return parts.length >= 2 ? parts[1] : '';
}

function parseUnlocked(raw: string | null): string[] {
  if (!raw) return [];
  try {
    const v = JSON.parse(raw);
    return Array.isArray(v) ? v : [];
  } catch {
    return [];
  }
}

// POST /api/devices/register
router.post('/register', (req: Request, res: Response) => {
  const { deviceToken } = req.body;

  if (!deviceToken || typeof deviceToken !== 'string') {
    res.status(400).json({ error: 'deviceToken is required' });
    return;
  }

  const db = getDb();

  const existing = db.prepare('SELECT id, delivered_count FROM devices WHERE device_token = ?').get(deviceToken) as
    | { id: number; delivered_count: number | null }
    | undefined;

  if (existing) {
    db.prepare("UPDATE devices SET updated_at = datetime('now') WHERE id = ?").run(existing.id);
    res.json({ deviceId: existing.id, deliveredCount: existing.delivered_count ?? 0 });
    return;
  }

  const result = db.prepare('INSERT INTO devices (device_token) VALUES (?)').run(deviceToken);
  res.status(201).json({ deviceId: result.lastInsertRowid, deliveredCount: 0 });
});

// GET /api/devices/me?deviceToken=... — 디바이스 진행도(배송완료 누적 카운트 + 해제 부품) 조회
router.get('/me', (req: Request, res: Response) => {
  const { deviceToken } = req.query;

  if (!deviceToken || typeof deviceToken !== 'string') {
    res.status(400).json({ error: 'deviceToken query param is required' });
    return;
  }

  const db = getDb();
  const device = db.prepare('SELECT id, delivered_count, unlocked_parts FROM devices WHERE device_token = ?').get(deviceToken) as
    | { id: number; delivered_count: number | null; unlocked_parts: string | null }
    | undefined;

  if (!device) {
    res.status(404).json({ error: 'Device not registered' });
    return;
  }

  res.json({
    deviceId: device.id,
    deliveredCount: device.delivered_count ?? 0,
    unlockedParts: parseUnlocked(device.unlocked_parts),
  });
});

// POST /api/devices/unlock-part — 포인트로 부품 1개 해제 (탱크·기차·물탱크·건설·컨테이너는 거부)
router.post('/unlock-part', (req: Request, res: Response) => {
  const { deviceToken, part } = req.body;

  if (!deviceToken || typeof deviceToken !== 'string' || !part || typeof part !== 'string') {
    res.status(400).json({ error: 'deviceToken, part are required' });
    return;
  }
  if (!POINT_UNLOCKABLE_FAMILIES.has(familyToken(part))) {
    res.status(403).json({ error: 'This part is Plus only and cannot be unlocked with points' });
    return;
  }

  const db = getDb();
  const device = db.prepare('SELECT id, delivered_count, unlocked_parts FROM devices WHERE device_token = ?').get(deviceToken) as
    | { id: number; delivered_count: number | null; unlocked_parts: string | null }
    | undefined;
  if (!device) {
    res.status(404).json({ error: 'Device not registered' });
    return;
  }

  const delivered = device.delivered_count ?? 0;
  const unlocked = parseUnlocked(device.unlocked_parts);

  // 이미 해제됐으면 멱등 처리
  if (unlocked.includes(part)) {
    res.json({ deliveredCount: delivered, unlockedParts: unlocked });
    return;
  }

  const balance = delivered - unlocked.length * POINT_UNLOCK_COST;
  if (balance < POINT_UNLOCK_COST) {
    res.status(400).json({ error: 'INSUFFICIENT_POINTS', balance });
    return;
  }

  unlocked.push(part);
  db.prepare("UPDATE devices SET unlocked_parts = ?, updated_at = datetime('now') WHERE id = ?")
    .run(JSON.stringify(unlocked), device.id);

  res.json({ deliveredCount: delivered, unlockedParts: unlocked });
});

// PUT /api/devices/apns-token — 표준 원격알림(일반 배너)용 APNs device token 등록
router.put('/apns-token', (req: Request, res: Response) => {
  const { deviceToken, apnsToken } = req.body;

  if (!deviceToken || typeof deviceToken !== 'string' || !apnsToken || typeof apnsToken !== 'string') {
    res.status(400).json({ error: 'deviceToken, apnsToken are required' });
    return;
  }
  // APNs device token 은 hex 문자열. 형식/길이 검증으로 쓰레기 값 저장 방지.
  if (!/^[0-9a-fA-F]+$/.test(apnsToken) || apnsToken.length > 200) {
    res.status(400).json({ error: 'apnsToken must be a hex string' });
    return;
  }

  const db = getDb();
  const result = db.prepare(
    "UPDATE devices SET apns_token = ?, updated_at = datetime('now') WHERE device_token = ?"
  ).run(apnsToken, deviceToken);

  if (result.changes === 0) {
    res.status(404).json({ error: 'Device not registered. Call POST /api/devices/register first' });
    return;
  }

  // APNs token 은 (기기,앱설치)당 하나 — 같은 토큰을 가진 다른 device 행이 있으면 정리해
  // 한 번의 상태 변경에 같은 단말로 배너가 중복 발사되는 것을 막는다.
  db.prepare('UPDATE devices SET apns_token = NULL WHERE apns_token = ? AND device_token <> ?')
    .run(apnsToken, deviceToken);

  res.json({ success: true });
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
