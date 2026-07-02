import { DeliveryStatus, STATUS_T_VALUES } from '../types/delivery.js';

/**
 * tracker.delivery 상태 코드를 Waito DeliveryStatus로 1:1 매핑한다.
 * (택배사 coarse 코드 그대로 — 상차/하차·배송중 세분화는 문구 추측이라 폐기)
 * IN_TRANSIT → inTransitIn(간선), OUT_FOR_DELIVERY → outForDelivery(배송출발).
 */
export function mapTrackerStatus(
  trackerCode: string,
  _description: string = '',
): DeliveryStatus | null {
  switch (trackerCode) {
    case 'INFORMATION_RECEIVED':
      return DeliveryStatus.Registered;

    case 'AT_PICKUP':
      return DeliveryStatus.PickedUp;

    case 'IN_TRANSIT':
      return DeliveryStatus.InTransitIn;

    case 'OUT_FOR_DELIVERY':
      return DeliveryStatus.OutForDelivery;

    case 'DELIVERED':
      return DeliveryStatus.Delivered;

    // ATTEMPT_FAIL / EXCEPTION / UNKNOWN 등 진행 아님 → 현재 상태 유지
    default:
      return null;
  }
}

/**
 * 트럭은 절대 뒤로 가지 않는다.
 * 새 상태의 t값이 현재 t값보다 크거나 같을 때만 업데이트를 허용한다.
 */
export function shouldUpdateStatus(
  currentStatus: DeliveryStatus,
  newStatus: DeliveryStatus,
): boolean {
  return STATUS_T_VALUES[newStatus] > STATUS_T_VALUES[currentStatus];
}

/**
 * tracker.delivery 이벤트를 처리하여 최종 상태를 결정한다.
 * 현재 상태보다 뒤로 가는 매핑은 무시한다.
 */
export function resolveNewStatus(
  currentStatus: DeliveryStatus,
  trackerCode: string,
  description: string = '',
): DeliveryStatus {
  const mapped = mapTrackerStatus(trackerCode, description);
  if (mapped === null) return currentStatus;
  if (!shouldUpdateStatus(currentStatus, mapped)) return currentStatus;
  return mapped;
}
