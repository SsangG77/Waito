import { GraphQLClient, gql, ClientError } from 'graphql-request';
import { config } from '../config.js';
import type { TrackerDeliveryResponse } from '../types/delivery.js';
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

export async function trackPackage(
  carrierId: string,
  trackingNumber: string,
): Promise<TrackerDeliveryResponse> {
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
