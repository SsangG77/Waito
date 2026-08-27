import { DeliveryStatus, STATUS_T_VALUES, type CarrierProvider } from '../types/delivery.js';

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
 * 17TRACK 상태 코드를 Waito DeliveryStatus 로 매핑한다.
 *
 * 해외 배송에는 통관 대기·픽업 보관·배송 실패처럼 국내 5단계에 없는 구간이 있다.
 * 타임라인 단계를 늘리면 앱·위젯 3면을 모두 고쳐야 하므로, 우선 5단계에 접어 넣고
 * 구체적인 상황은 이벤트 원본 문구(statusLabel)로 전달한다.
 * → 통관은 '간선'으로 접힌다. 단계를 늘릴지는 실제 해외 배송 데이터를 본 뒤 판단.
 */
export function mapTrack17Status(
  code: string,
  _description: string = '',
): DeliveryStatus | null {
  switch (code) {
    case 'InfoReceived':
      return DeliveryStatus.Registered;

    // 통관(Customs)·항공 이동 등 이동 구간 전부. 17TRACK 의 sub_status 로 세분화되지만
    // 표시 단계는 간선 하나로 접는다.
    case 'InTransit':
      return DeliveryStatus.InTransitIn;

    // 픽업 보관(영업점 도착)도 "곧 받는다"는 의미라 배송출발과 같은 단계로 본다.
    case 'AvailableForPickup':
    case 'OutForDelivery':
      return DeliveryStatus.OutForDelivery;

    case 'Delivered':
      return DeliveryStatus.Delivered;

    // NotFound(미조회) / Expired(만료) / DeliveryFailure(배송실패) / Exception(문제)
    // → 진행이 아니므로 현재 상태 유지
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
 * 이벤트 하나를 처리해 최종 상태를 결정한다.
 * 현재 상태보다 뒤로 가는 매핑은 무시한다.
 *
 * provider 로 어느 코드 체계인지 구분한다(기본값은 국내 tracker.delivery).
 */
export function resolveNewStatus(
  currentStatus: DeliveryStatus,
  trackerCode: string,
  description: string = '',
  provider: CarrierProvider = 'tracker',
): DeliveryStatus {
  const mapped = provider === 'track17'
    ? mapTrack17Status(trackerCode, description)
    : mapTrackerStatus(trackerCode, description);
  if (mapped === null) return currentStatus;
  if (!shouldUpdateStatus(currentStatus, mapped)) return currentStatus;
  return mapped;
}
