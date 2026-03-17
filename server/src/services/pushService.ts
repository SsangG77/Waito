import { DeliveryStatus, STATUS_T_VALUES } from '../types/delivery.js';
import { config } from '../config.js';
import { getDb } from '../db/database.js';

interface LiveActivityContentState {
  status: DeliveryStatus;
  carrierName: string;
  itemName: string;
  estimatedDelivery: string | null;
}

const STATUS_DESCRIPTIONS: Record<DeliveryStatus, string> = {
  [DeliveryStatus.Registered]: '택배가 접수되었습니다',
  [DeliveryStatus.PickedUp]: '택배가 집화 완료되었습니다',
  [DeliveryStatus.InTransitIn]: '택배가 간선상차 되었습니다',
  [DeliveryStatus.InTransitOut]: '택배가 간선하차 되었습니다',
  [DeliveryStatus.OutForDelivery]: '배송이 출발했습니다',
  [DeliveryStatus.Delivering]: '택배가 배송중입니다',
  [DeliveryStatus.Delivered]: '택배가 배송 완료되었습니다',
};

/**
 * APNs를 통해 Live Activity를 업데이트한다.
 * MVP에서는 HTTP/2 직접 호출로 구현한다.
 */
export async function sendLiveActivityUpdate(
  pushToken: string,
  contentState: LiveActivityContentState,
  isEnd: boolean = false,
): Promise<boolean> {
  const payload = {
    aps: {
      timestamp: Math.floor(Date.now() / 1000),
      event: isEnd ? 'end' : 'update',
      'content-state': contentState,
      alert: {
        title: '배송 상태 업데이트',
        body: STATUS_DESCRIPTIONS[contentState.status],
      },
    },
  };

  try {
    // APNs HTTP/2 push
    // TODO: Implement actual APNs HTTP/2 call with JWT auth
    // For now, log the payload for development
    console.log(`[APNs] ${isEnd ? 'END' : 'UPDATE'} push to ${pushToken.substring(0, 8)}...`);
    console.log(`[APNs] Status: ${contentState.status}, Carrier: ${contentState.carrierName}`);

    // Placeholder: In production, use HTTP/2 client with JWT
    // const response = await apnsHttp2Request(pushToken, payload);
    // return response.status === 200;

    return true;
  } catch (error) {
    console.error(`[APNs] Push failed for token ${pushToken.substring(0, 8)}...:`, error);
    return false;
  }
}

/**
 * 추적 ID에 해당하는 Live Activity를 업데이트한다.
 * push token이 없으면 무시한다.
 */
export async function pushTrackingUpdate(
  trackingId: number,
  status: DeliveryStatus,
): Promise<void> {
  const db = getDb();
  const tracking = db.prepare(
    'SELECT live_activity_push_token, carrier_name, item_name, estimated_delivery FROM trackings WHERE id = ?'
  ).get(trackingId) as {
    live_activity_push_token: string | null;
    carrier_name: string;
    item_name: string;
    estimated_delivery: string | null;
  } | undefined;

  if (!tracking?.live_activity_push_token) return;

  const isEnd = status === DeliveryStatus.Delivered;
  const success = await sendLiveActivityUpdate(
    tracking.live_activity_push_token,
    {
      status,
      carrierName: tracking.carrier_name,
      itemName: tracking.item_name,
      estimatedDelivery: tracking.estimated_delivery,
    },
    isEnd,
  );

  if (!success) {
    // 3회 재시도
    for (let i = 0; i < 2; i++) {
      const retrySuccess = await sendLiveActivityUpdate(
        tracking.live_activity_push_token,
        {
          status,
          carrierName: tracking.carrier_name,
          itemName: tracking.item_name,
          estimatedDelivery: tracking.estimated_delivery,
        },
        isEnd,
      );
      if (retrySuccess) return;
    }

    // 모든 재시도 실패 시 토큰 무효화
    console.warn(`[APNs] Invalidating push token for tracking ${trackingId}`);
    db.prepare('UPDATE trackings SET live_activity_push_token = NULL WHERE id = ?').run(trackingId);
  }
}
