import cron from 'node-cron';
import { config } from '../config.js';
import { getDb } from '../db/database.js';
import { CARRIERS } from '../types/delivery.js';

/**
 * 국내 허브명 → 좌표 변환 (카카오 장소 검색).
 *
 * 배송 이력에 쌓인 위치 문자열("옥천HUB", "서울강남" 등)을 좌표로 바꿔 hub_locations 에 저장한다.
 * 한 이름당 딱 한 번만 호출하고 이후는 대응표를 재사용 → 무료 한도 안에서 끝난다.
 *
 * 국내 전용. 해외(17TRACK) 위치는 카카오 검색 정확도가 낮아 대상에서 제외한다.
 * 키가 없으면 아무 것도 하지 않는다(실패로 기록하지 않음 → 나중에 키를 넣으면 그대로 처리됨).
 */

const REQUEST_TIMEOUT_MS = 5_000;

/// 한 사이클에 변환할 이름 수. 스케줄러가 반복 실행하므로 밀린 것도 결국 다 처리된다.
const BATCH_SIZE = 30;

/// 연속 호출 간 간격 — 카카오 초당 제한에 걸리지 않도록.
const CALL_INTERVAL_MS = 200;

/// 한반도 대략 범위. 검색이 엉뚱한 동명 장소(해외 등)를 물어오는 것을 걸러낸다.
const KOREA_BOUNDS = { minLat: 33, maxLat: 39, minLon: 124, maxLon: 132 };

const DOMESTIC_CARRIER_IDS = CARRIERS.filter(c => c.provider === 'tracker').map(c => c.id);

export interface HubCoords {
  lat: number;
  lon: number;
}

export function isKakaoConfigured(): boolean {
  return config.kakao.restApiKey.length > 0;
}

/** 좌표가 한반도 범위 안인지. 카카오가 x=경도 / y=위도 로 주므로 뒤바뀐 값도 여기서 걸러진다. */
export function isInKorea(coords: HubCoords): boolean {
  return (
    coords.lat >= KOREA_BOUNDS.minLat &&
    coords.lat <= KOREA_BOUNDS.maxLat &&
    coords.lon >= KOREA_BOUNDS.minLon &&
    coords.lon <= KOREA_BOUNDS.maxLon
  );
}

/**
 * 검색어 후보. 원문으로 먼저 찾고, 안 나오면 허브 접미사를 뗀 지명으로 한 번 더 시도한다.
 * ("옥천HUB" 는 검색이 안 되지만 "옥천" 은 나오는 식)
 */
export function searchVariants(name: string): string[] {
  const raw = name.trim();
  const stripped = raw.replace(/\s*(HUB|Hub|hub|허브|터미널|물류센터)\s*$/, '').trim();
  return stripped && stripped !== raw ? [raw, stripped] : [raw];
}

/** 카카오 응답에서 첫 장소의 좌표를 뽑는다. x=경도, y=위도. */
export function parseKakaoCoords(body: unknown): HubCoords | null {
  const documents = (body as { documents?: Array<{ x?: string; y?: string }> })?.documents;
  const first = documents?.[0];
  if (!first?.x || !first?.y) return null;

  const coords = { lat: Number(first.y), lon: Number(first.x) };
  if (!Number.isFinite(coords.lat) || !Number.isFinite(coords.lon)) return null;
  return isInKorea(coords) ? coords : null;
}

async function searchKakao(query: string): Promise<HubCoords | null> {
  const url = `${config.kakao.apiUrl}?query=${encodeURIComponent(query)}&size=1`;
  const res = await fetch(url, {
    headers: { Authorization: `KakaoAK ${config.kakao.restApiKey}` },
    signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
  });

  if (!res.ok) {
    throw new Error(`[Kakao] HTTP ${res.status} (${query})`);
  }
  return parseKakaoCoords(await res.json());
}

/** 허브명 하나를 좌표로. 못 찾으면 null. */
export async function geocodeHub(name: string): Promise<HubCoords | null> {
  for (const query of searchVariants(name)) {
    const coords = await searchKakao(query);
    if (coords) return coords;
  }
  return null;
}

export interface HubRow {
  name: string;
  lat: number | null;
  lon: number | null;
  status: string;
  source: string;
  updated_at: string;
  /** 이 허브명이 배송 이력에 나온 횟수 — 자주 나오는 것부터 손보게 정렬 근거로 쓴다. */
  uses: number;
}

/** 관리자 화면용 — 대응표 전체(실패 먼저, 그다음 사용 빈도순). */
export function listHubs(): HubRow[] {
  return getDb()
    .prepare(
      `SELECT h.name, h.lat, h.lon, h.status, h.source, h.updated_at,
              (SELECT COUNT(*) FROM tracking_events e WHERE e.location = h.name) AS uses
         FROM hub_locations h
        ORDER BY (h.status = 'ok') ASC, uses DESC, h.name ASC`,
    )
    .all() as HubRow[];
}

/** 아직 변환 시도조차 안 된 이름 수(다음 주기에 처리될 대기 물량). */
export function countUnmappedHubs(): number {
  return findUnmappedHubNames(100_000).length;
}

/** 관리자가 좌표를 직접 넣는다. 카카오가 못 찾은 허브를 살리는 최종 수단. */
export function saveManualHub(name: string, lat: number, lon: number): void {
  saveHub(name, { lat, lon }, 'manual');
}

/** 실패 표시를 지워 다음 주기에 다시 검색되게 한다(카카오 일시 오류로 실패한 경우). */
export function retryHub(name: string): void {
  getDb().prepare('DELETE FROM hub_locations WHERE name = ?').run(name);
}

/** 아직 대응표에 없는 국내 허브명 목록. 새로 들어온 이력과 과거 이력을 같은 경로로 처리한다. */
function findUnmappedHubNames(limit: number): string[] {
  const placeholders = DOMESTIC_CARRIER_IDS.map(() => '?').join(',');
  const rows = getDb()
    .prepare(
      `SELECT DISTINCT e.location AS name
         FROM tracking_events e
         JOIN trackings t ON t.id = e.tracking_id
        WHERE e.location IS NOT NULL
          AND TRIM(e.location) <> ''
          AND t.carrier_id IN (${placeholders})
          AND e.location NOT IN (SELECT name FROM hub_locations)
        LIMIT ?`,
    )
    .all(...DOMESTIC_CARRIER_IDS, limit) as Array<{ name: string }>;

  return rows.map(r => r.name);
}

function saveHub(name: string, coords: HubCoords | null, source = 'kakao'): void {
  getDb()
    .prepare(
      `INSERT INTO hub_locations (name, lat, lon, status, source, updated_at)
       VALUES (?, ?, ?, ?, ?, datetime('now'))
       ON CONFLICT(name) DO UPDATE SET
         lat = excluded.lat, lon = excluded.lon,
         status = excluded.status, source = excluded.source,
         updated_at = excluded.updated_at`,
    )
    .run(name, coords?.lat ?? null, coords?.lon ?? null, coords ? 'ok' : 'failed', source);
}

/**
 * 미변환 허브명을 한 배치 처리. 처리한 개수를 반환한다.
 * 실패한 이름은 'failed' 로 남겨 매번 다시 호출하지 않는다(관리자 수동 입력 대상).
 */
export async function resolveUnmappedHubs(limit = BATCH_SIZE): Promise<number> {
  if (!isKakaoConfigured()) return 0;

  const names = findUnmappedHubNames(limit);
  let done = 0;

  for (const name of names) {
    try {
      saveHub(name, await geocodeHub(name));
      done++;
    } catch (error) {
      // 네트워크/한도 오류는 기록하지 않고 다음 사이클에 재시도한다.
      console.error(`[Kakao] 좌표 변환 실패 (${name}):`, error);
    }
    await new Promise(resolve => setTimeout(resolve, CALL_INTERVAL_MS));
  }

  return done;
}

/**
 * 허브 좌표 변환 스케줄러 — 10분마다 미변환 이름을 처리한다.
 * 새로 들어온 이력과 과거에 쌓인 이력이 같은 경로를 타므로 별도 일괄 변환 작업이 필요 없다.
 */
export function startHubGeocodeScheduler(): void {
  if (!isKakaoConfigured()) {
    console.log('[Kakao] REST 키 미설정 — 허브 좌표 변환 비활성');
    return;
  }

  cron.schedule('*/10 * * * *', async () => {
    try {
      const done = await resolveUnmappedHubs();
      if (done > 0) console.log(`[Kakao] 허브 좌표 변환 ${done}건`);
    } catch (error) {
      console.error('[Kakao] 허브 좌표 변환 사이클 실패:', error);
    }
  });
}
