import { GraphQLClient, gql, ClientError } from 'graphql-request';
import { config } from '../config.js';
import type { TrackerDeliveryResponse, TrackerDeliveryEvent } from '../types/delivery.js';
import { markCredentialExpired } from './credentialMonitor.js';

const TRACK_QUERY = gql`
  query Track($carrierId: ID!, $trackingNumber: String!) {
    track(carrierId: $carrierId, trackingNumber: $trackingNumber) {
      lastEvent {
        time
        status {
          code
        }
      }
      events(last: 50) {
        edges {
          node {
            time
            status {
              code
            }
            description
          }
        }
      }
    }
  }
`;

let client: GraphQLClient | null = null;

function getClient(): GraphQLClient {
  if (!client) {
    client = new GraphQLClient(config.tracker.apiUrl, {
      headers: {
        'Authorization': `TRACKQL-API-KEY ${config.tracker.clientId}:${config.tracker.clientSecret}`,
      },
    });
  }
  return client;
}

/**
 * credential이 갱신되었을 때 GraphQL 클라이언트를 재생성한다.
 */
export function resetClient(): void {
  client = null;
}

/** 개발/테스트용 운송장번호 — tracker.delivery 실제 조회 없이 더미 배송 데이터를 응답한다. */
export const TEST_TRACKING_NUMBER = 'test970719';

/** 테스트 더미 단계 진행 간격 — created_at 기준 2시간마다 1칸 전진. */
export const TEST_STEP_INTERVAL_MS = 2 * 60 * 60 * 1000;

/** 5단계(접수→집화→간선→배송출발→배송완료) = 택배사 코드 그대로. 배송완료 후 2시간 뒤 접수로 순환. */
export const TEST_STEPS: ReadonlyArray<{ code: string; description: string; location: string }> = [
  { code: 'INFORMATION_RECEIVED', description: '접수',       location: '서울 강남' },
  { code: 'AT_PICKUP',            description: '집화처리',   location: '서울 강남' },
  { code: 'IN_TRANSIT',           description: '간선 이동중', location: '옥천HUB' },
  { code: 'OUT_FOR_DELIVERY',     description: '배송출발',   location: '부산 해운대' },
  { code: 'DELIVERED',            description: '배송완료',   location: '부산 해운대' },
];

/** created_at(ms) 기준 현재 단계 인덱스 — 2시간마다 +1, 5단계 순환(배송완료 → 2h 후 접수). */
export function testStepIndex(createdAtMs: number, nowMs: number = Date.now()): number {
  const elapsed = Math.max(0, nowMs - createdAtMs);
  return Math.floor(elapsed / TEST_STEP_INTERVAL_MS) % TEST_STEPS.length;
}

/** 추가(POST)용 — created_at 기준 현재 단계까지의 더미 이벤트 응답. */
function buildTestTrackResponse(createdAtMs: number): TrackerDeliveryResponse {
  const step = testStepIndex(createdAtMs);
  const edges: Array<{ node: TrackerDeliveryEvent }> = [];
  for (let i = 0; i <= step; i++) {
    const s = TEST_STEPS[i];
    edges.push({
      node: {
        time: new Date(createdAtMs + i * TEST_STEP_INTERVAL_MS).toISOString(),
        status: { code: s.code },
        description: s.description,
        location: s.location,
      },
    });
  }
  const last = edges[edges.length - 1].node;
  return {
    track: {
      lastEvent: { time: last.time, status: last.status },
      events: { edges },
    },
  };
}

export async function trackPackage(
  carrierId: string,
  trackingNumber: string,
  createdAtMs?: number,
): Promise<TrackerDeliveryResponse> {
  if (trackingNumber === TEST_TRACKING_NUMBER) {
    return buildTestTrackResponse(createdAtMs ?? Date.now());
  }
  try {
    return await getClient().request<TrackerDeliveryResponse>(TRACK_QUERY, {
      carrierId,
      trackingNumber,
    });
  } catch (error) {
    if (error instanceof ClientError && error.response.status === 401) {
      markCredentialExpired();
    }
    throw error;
  }
}

/**
 * track 조회 에러가 "운송장 미등록/조회 불가(NOT_FOUND)"인지 판별한다.
 * (잘못된 번호 / 배송 준비중 / 데이터 만료를 API가 구분하지 못하므로 통칭)
 */
export function isTrackingNotFoundError(error: unknown): boolean {
  return (
    error instanceof ClientError &&
    (error.response.errors?.some(e => e.extensions?.code === 'NOT_FOUND') ?? false)
  );
}

// 최신 API: registerTrackWebhook 은 Boolean 을 반환하므로 subfield 를 선택하지 않는다.
// 등록 해제는 별도 mutation 없이 expirationTime 에 과거 시각을 넣어 호출하면 되며,
// 일반적으로는 TTL 만료로 자동 해제되도록 두는 것을 권장한다.
const REGISTER_WEBHOOK_MUTATION = gql`
  mutation RegisterTrackWebhook($input: RegisterTrackWebhookInput!) {
    registerTrackWebhook(input: $input)
  }
`;

/// webhook 유효 기간. 권장값(현재 + 48시간). keep-alive 로 24시간마다 갱신한다.
const WEBHOOK_TTL_HOURS = 48;

export async function registerWebhook(
  carrierId: string,
  trackingNumber: string,
  callbackUrl: string,
): Promise<{ expiresAt: string }> {
  const expiresAt = new Date(Date.now() + WEBHOOK_TTL_HOURS * 60 * 60 * 1000).toISOString();
  // 테스트 운송장은 존재하지 않는 번호라 실제 webhook 등록을 건너뛴다(API 가 거부함).
  if (trackingNumber === TEST_TRACKING_NUMBER) {
    return { expiresAt };
  }
  await getClient().request(REGISTER_WEBHOOK_MUTATION, {
    input: {
      carrierId,
      trackingNumber,
      callbackUrl,
      expirationTime: expiresAt,
    },
  });
  return { expiresAt };
}
