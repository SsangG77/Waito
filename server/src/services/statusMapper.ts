import { DeliveryStatus, STATUS_T_VALUES } from '../types/delivery.js';

const IN_TRANSIT_KEYWORDS = {
  inTransitIn: ['상차', '집하', '발송'],
  inTransitOut: ['하차', '도착', '배달준비'],
} as const;

const OUT_FOR_DELIVERY_KEYWORDS = {
  delivering: ['배송중', '배달중'],
} as const;

/**
 * tracker.delivery 상태 코드를 Waito DeliveryStatus로 매핑한다.
 * description(한국어)으로 IN_TRANSIT / OUT_FOR_DELIVERY를 세분화한다.
 */
export function mapTrackerStatus(
  trackerCode: string,
  description: string = '',
): DeliveryStatus | null {
  switch (trackerCode) {
    case 'INFORMATION_RECEIVED':
      return DeliveryStatus.Registered;

    case 'AT_PICKUP':
      return DeliveryStatus.PickedUp;

    case 'IN_TRANSIT': {
      // 한국어 키워드 매칭으로 세분화
      for (const keyword of IN_TRANSIT_KEYWORDS.inTransitOut) {
        if (description.includes(keyword)) {
          return DeliveryStatus.InTransitOut;
        }
      }
      for (const keyword of IN_TRANSIT_KEYWORDS.inTransitIn) {
        if (description.includes(keyword)) {
          return DeliveryStatus.InTransitIn;
        }
      }
      // 키워드 없으면 기본 inTransitIn
      return DeliveryStatus.InTransitIn;
    }

    case 'OUT_FOR_DELIVERY': {
      for (const keyword of OUT_FOR_DELIVERY_KEYWORDS.delivering) {
        if (description.includes(keyword)) {
          return DeliveryStatus.Delivering;
        }
      }
      return DeliveryStatus.OutForDelivery;
    }

    case 'DELIVERED':
      return DeliveryStatus.Delivered;

    case 'ATTEMPT_FAIL':
    case 'EXCEPTION':
    case 'UNKNOWN':
      return null; // 현재 상태 유지

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
