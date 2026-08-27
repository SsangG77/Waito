import { config } from '../config.js';
import type { TrackerDeliveryResponse, TrackerDeliveryEvent } from '../types/delivery.js';

/**
 * 17TRACK(REST) 클라이언트 — 해외 택배사 조회.
 *
 * tracker.delivery 와 달리 "등록 후 조회" 2단계다. 등록 시점에만 quota 1건이 차감되고
 * 이후 조회·재조회는 무과금이라 폴링 주기를 줄여도 비용이 늘지 않는다.
 *
 * 응답은 tracker.delivery 와 같은 모양(TrackerDeliveryResponse)으로 변환해서 돌려준다.
 * → pollTracking 의 이벤트 처리·상태 판정 로직을 제공자별로 나누지 않아도 된다.
 */

/// 요청 단위 상한. 폴링이 직렬이라 한 건이 매달리면 사이클 전체가 멈춘다.
const REQUEST_TIMEOUT_MS = 10_000;

/// 아직 조회 결과가 없을 때. pollTracking 의 `!result.track?.lastEvent` 가드에 걸려 그대로 넘어간다.
const EMPTY_TRACK: TrackerDeliveryResponse = {
  track: { lastEvent: null, events: { edges: [] } },
};

/** 17TRACK 이 쓰는 상태 코드. 우리 5단계 매핑은 statusMapper 가 담당한다. */
export type Track17Status =
  | 'NotFound'
  | 'InfoReceived'
  | 'InTransit'
  | 'Expired'
  | 'AvailableForPickup'
  | 'OutForDelivery'
  | 'DeliveryFailure'
  | 'Delivered'
  | 'Exception';

export function isTrack17Configured(): boolean {
  return config.track17.apiKey.length > 0;
}

async function request<T>(path: string, body: unknown): Promise<T> {
  if (!isTrack17Configured()) {
    throw new Error('[17TRACK] API key not configured');
  }

  const res = await fetch(`${config.track17.apiUrl}${path}`, {
    method: 'POST',
    headers: {
      '17token': config.track17.apiKey,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(body),
    signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
  });

  if (!res.ok) {
    throw new Error(`[17TRACK] HTTP ${res.status} on ${path}`);
  }
  return (await res.json()) as T;
}

/**
 * 운송장 등록 — **quota 가 차감되는 유일한 지점**.
 * 이미 등록된 운송장을 다시 등록해도 중복 차감되지 않는다(코드 -18019690 = already registered).
 */
export async function registerTracking(
  carrierKey: string,
  trackingNumber: string,
): Promise<void> {
  const result = await request<{
    code: number;
    data: {
      accepted?: Array<{ number: string }>;
      rejected?: Array<{ number: string; error: { code: number; message: string } }>;
    };
  }>('/register', [
    { number: trackingNumber, carrier: Number(carrierKey) },
  ]);

  const rejected = result.data?.rejected?.[0];
  if (!rejected) return;

  // -18019901 = already registered. 재등록은 차감이 없고 정상 상황이라 통과시킨다.
  if (rejected.error.code === -18019901) return;

  throw new Error(
    `[17TRACK] register rejected (${rejected.error.code}): ${rejected.error.message}`,
  );
}

/**
 * 추적 정보 조회 — 무과금. 등록되지 않은 운송장이면 자동으로 한 번 등록하고 다시 조회한다.
 */
export async function trackPackage17(
  carrierKey: string,
  trackingNumber: string,
): Promise<TrackerDeliveryResponse> {
  let info = await fetchTrackInfo(carrierKey, trackingNumber);

  // 미등록 상태면 등록 후 재조회 (앱에서 추가된 직후 첫 폴링이 여기 해당)
  if (!info) {
    await registerTracking(carrierKey, trackingNumber);
    info = await fetchTrackInfo(carrierKey, trackingNumber);
  }

  if (!info) {
    return EMPTY_TRACK;
  }
  return toTrackerShape(info);
}

interface Track17Event {
  time_iso?: string;
  time_utc?: string;
  description?: string;
  location?: string;
  stage?: string;
  sub_status?: string;
}

interface Track17Accepted {
  number: string;
  track_info?: {
    latest_status?: { status?: string; sub_status?: string };
    tracking?: {
      providers?: Array<{ events?: Track17Event[] }>;
    };
  };
}

async function fetchTrackInfo(
  carrierKey: string,
  trackingNumber: string,
): Promise<Track17Accepted | null> {
  const result = await request<{
    code: number;
    data: { accepted?: Track17Accepted[]; rejected?: unknown[] };
  }>('/gettrackinfo', [
    { number: trackingNumber, carrier: Number(carrierKey) },
  ]);

  const accepted = result.data?.accepted?.[0];
  if (!accepted?.track_info) return null;
  return accepted;
}

/**
 * 17TRACK 응답 → tracker.delivery 응답 모양으로 변환.
 *
 * 이벤트는 provider 별로 나뉘어 오는데(발송국·도착국 배송사가 다름) 전부 합쳐
 * 시간순으로 정렬한다. status.code 에는 17TRACK 상태 문자열을 그대로 담아
 * statusMapper 가 5단계로 접는다.
 */
function toTrackerShape(accepted: Track17Accepted): TrackerDeliveryResponse {
  const info = accepted.track_info!;
  const latestStatus = info.latest_status?.status || 'InTransit';

  const rawEvents: Track17Event[] = (info.tracking?.providers ?? [])
    .flatMap(p => p.events ?? []);

  const events: TrackerDeliveryEvent[] = rawEvents
    .map(e => {
      const time = e.time_iso || e.time_utc || '';
      return {
        time,
        // 개별 이벤트의 stage 가 있으면 그걸 쓰고, 없으면 최종 상태로 대체.
        status: { code: e.stage || latestStatus },
        description: e.description || '',
        location: e.location ? { name: e.location } : null,
      };
    })
    .filter(e => e.time)
    .sort((a, b) => new Date(a.time).getTime() - new Date(b.time).getTime());

  if (events.length === 0) {
    return EMPTY_TRACK;
  }

  const last = events[events.length - 1];
  return {
    track: {
      // 마지막 이벤트의 stage 보다 latest_status 가 정확하다(17TRACK 이 종합 판정한 값).
      lastEvent: { time: last.time, status: { code: latestStatus } },
      events: { edges: events.map(node => ({ node })) },
    },
  };
}
