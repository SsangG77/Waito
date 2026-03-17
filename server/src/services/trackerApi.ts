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

const REGISTER_WEBHOOK_MUTATION = gql`
  mutation RegisterWebhook($input: RegisterTrackWebhookInput!) {
    registerTrackWebhook(input: $input) {
      id
      expirationTime
    }
  }
`;

interface WebhookRegistrationResult {
  registerTrackWebhook: {
    id: string;
    expirationTime: string;
  };
}

export async function registerWebhook(
  carrierId: string,
  trackingNumber: string,
  callbackUrl: string,
): Promise<{ webhookId: string; expiresAt: string }> {
  const result = await getClient().request<WebhookRegistrationResult>(
    REGISTER_WEBHOOK_MUTATION,
    {
      input: {
        carrierId,
        trackingNumber,
        callbackUrl,
      },
    },
  );
  return {
    webhookId: result.registerTrackWebhook.id,
    expiresAt: result.registerTrackWebhook.expirationTime,
  };
}

const DELETE_WEBHOOK_MUTATION = gql`
  mutation DeleteWebhook($input: DeleteTrackWebhookInput!) {
    deleteTrackWebhook(input: $input)
  }
`;

export async function deleteWebhook(webhookId: string): Promise<void> {
  await getClient().request(DELETE_WEBHOOK_MUTATION, {
    input: { id: webhookId },
  });
}
