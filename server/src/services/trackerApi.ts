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
            location {
              name
            }
          }
        }
      }
    }
  }
`;

/// tracker API 요청 단위 상한. 폴링이 직렬이라 한 건이 매달리면 사이클 전체가 멈춘다.
const REQUEST_TIMEOUT_MS = 10_000;

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

/** 테스트 더미 단계 진행 간격 — created_at 기준 1시간마다 1칸 전진. */
export const TEST_STEP_INTERVAL_MS = 1 * 60 * 60 * 1000;

/** 5단계(접수→집화→간선→배송출발→배송완료) = 택배사 코드 그대로. 배송완료(마지막)에서 멈춤. */
export const TEST_STEPS: ReadonlyArray<{ code: string; description: string; location: string }> = [
  { code: 'INFORMATION_RECEIVED', description: '접수',       location: '서울 강남' },
  { code: 'AT_PICKUP',            description: '집화처리',   location: '서울 강남' },
  { code: 'IN_TRANSIT',           description: '간선 이동중', location: '옥천HUB' },
  { code: 'OUT_FOR_DELIVERY',     description: '배송출발',   location: '부산 해운대' },
  { code: 'DELIVERED',            description: '배송완료',   location: '부산 해운대' },
];

/** created_at(ms) 기준 현재 단계 인덱스 — TEST_STEP_INTERVAL_MS 마다 +1, 배송완료(마지막)에서 멈춤(순환 없음). 재등록 시 재시작. */
export function testStepIndex(createdAtMs: number, nowMs: number = Date.now()): number {
  const elapsed = Math.max(0, nowMs - createdAtMs);
  return Math.min(Math.floor(elapsed / TEST_STEP_INTERVAL_MS), TEST_STEPS.length - 1);
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
        location: { name: s.location },
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
    return await getClient().request<TrackerDeliveryResponse>({
      document: TRACK_QUERY,
      variables: { carrierId, trackingNumber },
      // 요청마다 새 signal — 재사용하면 첫 타임아웃 이후 영구 abort 된다.
      signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
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

/**
 * "운송장 번호는 10자리 혹은 12자리입니다." 같은 자릿수 오류인지 판별한다.
 * 같은 택배사로는 몇 번을 다시 물어도 결과가 같으므로 바로 조회를 멈춘다.
 * (오류 코드는 확인 못 함 — 운영 로그에 찍힌 문구로만 판별)
 */
export function isInvalidTrackingNumberError(error: unknown): boolean {
  return (
    error instanceof ClientError &&
    (error.response.errors?.some(e => /운송장 번호는.*자리/.test(e.message)) ?? false)
  );
}

/**
 * 기록용 한 줄 요약. ClientError 를 통째로 찍으면 message 안에 요청·응답 JSON 이 전부 들어가
 * 5분 주기 반복 오류마다 수 KB 씩 기록이 쌓인다 → 상태 코드와 GraphQL 오류 메시지만 남긴다.
 */
export function errorSummary(error: unknown): string {
  if (error instanceof ClientError) {
    const errs = error.response.errors
      ?.map(e => (e.extensions?.code ? `${e.extensions.code} ${e.message}` : e.message))
      .join('; ');
    return `GraphQL HTTP ${error.response.status}${errs ? ` ${errs}` : ''}`.slice(0, 300);
  }
  const text = error instanceof Error ? error.message : String(error);
  return text.split('\n')[0].slice(0, 300);
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
  await getClient().request({
    document: REGISTER_WEBHOOK_MUTATION,
    variables: {
      input: {
        carrierId,
        trackingNumber,
        callbackUrl,
        expirationTime: expiresAt,
      },
    },
    signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
  });
  return { expiresAt };
}
