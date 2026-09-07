import { Router, Request, Response } from 'express';
import { getDb } from '../db/database.js';
import { trackPackage, registerWebhook, isTrackingNotFoundError } from '../services/trackerApi.js';
import { trackPackage17, detectCarrier17 } from '../services/track17Api.js';
import { resolveNewStatus } from '../services/statusMapper.js';
import { pollTracking } from '../services/pollingService.js';
import { DeliveryStatus, STATUS_T_VALUES, CARRIERS, type Carrier } from '../types/delivery.js';
import { config } from '../config.js';

const router = Router();

/**
 * 운송장 번호만으로 택배사를 감지한다 (carrierId='auto').
 * 1) 국내: tracker.delivery 를 CARRIERS 순서대로 조회 — 이벤트가 나오는 택배사 채택.
 *    (한국 운송장은 자릿수가 12~13자리로 겹쳐 패턴 판별이 불가능 → 실조회가 정답)
 * 2) 전부 실패 시: 17TRACK 자동 감지(등록 시 carrier 생략) → 우리 해외 CARRIERS 와 매핑.
 *    지원 목록 밖 택배사로 감지되면 null (quota 1건 소모는 감수 — 드묾).
 */
async function detectCarrier(trackingNumber: string): Promise<Carrier | null> {
  for (const candidate of CARRIERS.filter(c => c.provider === 'tracker')) {
    try {
      const result = await trackPackage(candidate.trackerId, trackingNumber);
      if (result.track?.lastEvent) return candidate;
    } catch {
      // NOT_FOUND·오류 → 다음 후보
    }
  }

  const key = await detectCarrier17(trackingNumber);
  if (key) {
    const matched = CARRIERS.find(c => c.provider === 'track17' && c.trackerId === key);
    if (matched) return matched;
    console.warn(`[Detect] 17TRACK 감지 결과가 지원 목록 밖 (carrier key=${key})`);
  }
  return null;
}

// POST /api/trackings — 택배 추적 등록
router.post('/', async (req: Request, res: Response) => {
  const { deviceToken, carrierId, trackingNumber, itemName, memo, force } = req.body;

  if (!deviceToken || !carrierId || !trackingNumber) {
    res.status(400).json({ error: 'deviceToken, carrierId, trackingNumber are required' });
    return;
  }

  // 'auto' — 운송장 번호만으로 택배사를 감지한다.
  // 국내(tracker.delivery)를 순서대로 조회해 데이터가 나오는 택배사를 채택하고,
  // 전부 실패하면 17TRACK 자동 감지(해외)로 넘어간다.
  let carrier = carrierId === 'auto' ? await detectCarrier(trackingNumber) : CARRIERS.find(c => c.id === carrierId);
  if (!carrier) {
    if (carrierId === 'auto') {
      res.status(422).json({
        error: 'TRACKING_NOT_FOUND',
        message: '택배사를 자동으로 찾지 못했어요. 택배사를 직접 선택해주세요.',
      });
      return;
    }
    res.status(400).json({ error: 'Invalid carrierId' });
    return;
  }

  const db = getDb();

  // 디바이스 확인 — 없으면 즉시 생성(upsert). 클라이언트 Keychain 에 토큰이 있는데 서버 DB 가
  // 그 토큰을 잃은 경우(재배포/서버 전환/DB 리셋)에도 "Device not registered" 없이 자가 복구된다.
  let device = db.prepare('SELECT id FROM devices WHERE device_token = ?').get(deviceToken) as { id: number } | undefined;
  if (!device) {
    const inserted = db.prepare('INSERT INTO devices (device_token) VALUES (?)').run(deviceToken);
    device = { id: inserted.lastInsertRowid as number };
  }

  // 중복 확인
  const existing = db.prepare(
    'SELECT id FROM trackings WHERE device_id = ? AND carrier_id = ? AND tracking_number = ?'
  ).get(device.id, carrier.id, trackingNumber);
  if (existing) {
    res.status(409).json({ error: 'Tracking already exists' });
    return;
  }

  // 초기 조회 — 조회 불가(NOT_FOUND)이고 force 가 아니면 추가하지 않고 확인을 요청한다
  let initialStatus = DeliveryStatus.Registered;
  let lastEventTime: string | null = null;   // 조회 성공 시에만 채워짐 → null 이면 "아직 데이터 없음"
  // 등록 시점에 조회된 이벤트를 그대로 저장(폴링과 동일) — 저장하지 않으면 목록이 events:[] 로 와서
  // 앱 펼침 타임라인이 폴백(고정 5단계)으로 보이다가, 첫 폴링에 이벤트가 저장되는 순간 원본 메시지로
  // 확 바뀌는 flip 이 생긴다. (mapped_status 는 폴링과 같이 누적 계산)
  const initialEvents: Array<{
    code: string; mapped: DeliveryStatus; description: string; time: string;
    location: string | null; lat: number | null; lon: number | null;
  }> = [];
  try {
    // 해외(17TRACK)는 등록이 있어야 조회가 된다. 여기서 quota 1건이 차감되고,
    // 이후 폴링·재조회는 무과금이라 등록 지점을 이 한 곳으로 모은다.
    const result = carrier.provider === 'track17'
      ? await trackPackage17(carrier.trackerId, trackingNumber)
      : await trackPackage(carrier.trackerId, trackingNumber);
    if (result.track?.lastEvent) {
      lastEventTime = result.track.lastEvent.time;
    }
    if (result.track?.events?.edges) {
      for (const edge of result.track.events.edges) {
        initialStatus = resolveNewStatus(initialStatus, edge.node.status.code, edge.node.description, carrier.provider);
        initialEvents.push({
          code: edge.node.status.code,
          mapped: initialStatus,
          description: edge.node.description,
          time: edge.node.time,
          location: edge.node.location?.name || null,
          lat: edge.node.location?.lat ?? null,
          lon: edge.node.location?.lon ?? null,
        });
      }
    }
  } catch (error) {
    if (isTrackingNotFoundError(error) && !force) {
      res.status(422).json({
        error: 'TRACKING_NOT_FOUND',
        message: '운송장을 조회할 수 없습니다. 번호가 올바른지 확인해주세요. (배송 준비중이거나 배송이 종료된 운송장일 수 있어요)',
      });
      return;
    }
    console.warn(`[Tracking] Initial fetch failed, starting as registered:`, error);
  }

  // DB 삽입
  const insertResult = db.prepare(`
    INSERT INTO trackings (device_id, carrier_id, tracking_number, item_name, memo, current_status, current_t_value, carrier_name, last_event_time)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
  `).run(
    device.id,
    carrier.id,
    trackingNumber,
    itemName || '',
    memo || '',
    initialStatus,
    STATUS_T_VALUES[initialStatus],
    carrier.name,
    lastEventTime,
  );

  const trackingId = insertResult.lastInsertRowid as number;

  // 등록 시점 이벤트 저장 — 폴링과 동일(INSERT OR IGNORE). 이게 없으면 펼침 타임라인이 첫 폴링
  // 전까지 폴백(고정 5단계 라벨)으로 보이다가, 폴링 순간 과거분까지 원본 메시지로 flip 된다.
  if (initialEvents.length > 0) {
    const insertEvent = db.prepare(`
      INSERT OR IGNORE INTO tracking_events (tracking_id, tracker_status, mapped_status, description, event_time, location, lat, lon)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    `);
    for (const ev of initialEvents) {
      insertEvent.run(trackingId, ev.code, ev.mapped, ev.description, ev.time, ev.location, ev.lat, ev.lon);
    }
  }

  // Webhook 등록 시도 — tracker.delivery 전용.
  // 17TRACK 은 운송장별 등록이 아니라 대시보드에 콜백 URL 을 한 번 설정하는 방식이고,
  // TLSv1.2 이상을 요구하는데 현재 서버는 도메인 없는 HTTP 라 폴링으로만 갱신한다.
  if (carrier.provider === 'tracker') {
  try {
    const webhook = await registerWebhook(
      carrier.trackerId,
      trackingNumber,
      `${config.webhookBaseUrl}/webhooks/tracker`,
    );
    db.prepare('UPDATE trackings SET webhook_expires_at = ? WHERE id = ?')
      .run(webhook.expiresAt, trackingId);
  } catch (error) {
    console.warn(`[Tracking] Webhook registration failed, will rely on polling:`, error);
  }
  }

  res.status(201).json({
    id: trackingId,
    carrierId: carrier.id,   // 'auto' 요청이면 감지된 실제 택배사 id
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
    SELECT id, carrier_id, tracking_number, item_name, memo, current_status, current_t_value,
           carrier_name, estimated_delivery, created_at, updated_at, last_event_time, delivered_at,
           sub_stage
    FROM trackings WHERE device_id = ? ORDER BY created_at DESC
  `).all(device.id) as Array<{ id: number; carrier_id: string }>;

  // 각 택배의 원본 이벤트를 한 번에 읽어 id별로 묶어 붙인다(가변 타임라인용).
  let eventsByTracking: Record<number, unknown[]> = {};
  if (trackings.length > 0) {
    const ids = trackings.map((t) => t.id);
    const placeholders = ids.map(() => '?').join(',');
    // 좌표는 두 출처를 합친다 — 이벤트에 직접 저장된 값(해외 17TRACK)이 우선,
    // 없으면 허브 대응표(국내 허브명을 카카오로 변환해 둔 것)에서 채운다.
    const allEvents = db.prepare(
      `SELECT e.*, COALESCE(e.lat, h.lat) AS lat, COALESCE(e.lon, h.lon) AS lon
         FROM tracking_events e
         LEFT JOIN hub_locations h ON h.name = e.location AND h.status = 'ok'
        WHERE e.tracking_id IN (${placeholders})
        ORDER BY e.event_time ASC`
    ).all(...ids) as Array<{ tracking_id: number }>;
    eventsByTracking = allEvents.reduce((acc, ev) => {
      (acc[ev.tracking_id] ??= []).push(ev);
      return acc;
    }, {} as Record<number, unknown[]>);
  }

  // is_international: 해외 택배사 여부 — 앱이 6단계(통관 포함) 타임라인을 그릴지 판별하는 근거.
  res.json(trackings.map((t) => ({
    ...t,
    is_international: CARRIERS.find(c => c.id === t.carrier_id)?.international === true,
    events: eventsByTracking[t.id] ?? [],
  })));
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
    `SELECT e.*, COALESCE(e.lat, h.lat) AS lat, COALESCE(e.lon, h.lon) AS lon
       FROM tracking_events e
       LEFT JOIN hub_locations h ON h.name = e.location AND h.status = 'ok'
      WHERE e.tracking_id = ? ORDER BY e.event_time ASC`
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

// PUT /api/trackings/:id — 품명/메모 수정 (택배사·운송장번호는 '신원'이라 불변)
router.put('/:id', (req: Request, res: Response) => {
  const { itemName, memo } = req.body;

  const db = getDb();
  const result = db.prepare(
    "UPDATE trackings SET item_name = ?, memo = ?, updated_at = datetime('now') WHERE id = ?"
  ).run(itemName ?? '', memo ?? '', req.params.id);

  if (result.changes === 0) {
    res.status(404).json({ error: 'Tracking not found' });
    return;
  }

  const updated = db.prepare(`
    SELECT id, carrier_id, tracking_number, item_name, memo, current_status, current_t_value,
           carrier_name, estimated_delivery, created_at, updated_at, last_event_time, delivered_at
    FROM trackings WHERE id = ?
  `).get(req.params.id);

  res.json(updated);
});

// POST /api/trackings/:id/refresh — 수동 새로고침
router.post('/:id/refresh', async (req: Request, res: Response) => {
  const trackingId = parseInt(String(req.params.id), 10);
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
  // push token 을 받은 시점 = Live Activity 가 (다시) 시작된 시점 → 8시간 재시작 기준으로 기록
  const result = db.prepare(
    "UPDATE trackings SET live_activity_push_token = ?, live_activity_started_at = datetime('now'), updated_at = datetime('now') WHERE id = ?"
  ).run(pushToken, req.params.id);

  if (result.changes === 0) {
    res.status(404).json({ error: 'Tracking not found' });
    return;
  }

  res.json({ success: true });
});

export default router;
