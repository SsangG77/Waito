import { describe, it, expect } from 'vitest';
import { mapTrackerStatus, mapTrack17Status, shouldUpdateStatus, resolveNewStatus } from '../src/services/statusMapper.js';
import { DeliveryStatus } from '../src/types/delivery.js';

describe('mapTrackerStatus (택배사 코드 1:1)', () => {
  it('maps INFORMATION_RECEIVED to registered', () => {
    expect(mapTrackerStatus('INFORMATION_RECEIVED')).toBe(DeliveryStatus.Registered);
  });

  it('maps AT_PICKUP to pickedUp', () => {
    expect(mapTrackerStatus('AT_PICKUP')).toBe(DeliveryStatus.PickedUp);
  });

  it('maps IN_TRANSIT to inTransitIn regardless of description (세분화 폐기)', () => {
    expect(mapTrackerStatus('IN_TRANSIT')).toBe(DeliveryStatus.InTransitIn);
    expect(mapTrackerStatus('IN_TRANSIT', '대전HUB 상차')).toBe(DeliveryStatus.InTransitIn);
    expect(mapTrackerStatus('IN_TRANSIT', '서울HUB 하차')).toBe(DeliveryStatus.InTransitIn);
    expect(mapTrackerStatus('IN_TRANSIT', '배송지 도착')).toBe(DeliveryStatus.InTransitIn);
  });

  it('maps OUT_FOR_DELIVERY to outForDelivery regardless of description (세분화 폐기)', () => {
    expect(mapTrackerStatus('OUT_FOR_DELIVERY')).toBe(DeliveryStatus.OutForDelivery);
    expect(mapTrackerStatus('OUT_FOR_DELIVERY', '배송중')).toBe(DeliveryStatus.OutForDelivery);
    expect(mapTrackerStatus('OUT_FOR_DELIVERY', '배달중입니다')).toBe(DeliveryStatus.OutForDelivery);
  });

  it('maps DELIVERED to delivered', () => {
    expect(mapTrackerStatus('DELIVERED')).toBe(DeliveryStatus.Delivered);
  });

  it('returns null for non-progress codes', () => {
    expect(mapTrackerStatus('ATTEMPT_FAIL')).toBeNull();
    expect(mapTrackerStatus('EXCEPTION')).toBeNull();
    expect(mapTrackerStatus('UNKNOWN')).toBeNull();
    expect(mapTrackerStatus('SOMETHING_ELSE')).toBeNull();
  });
});

describe('shouldUpdateStatus', () => {
  it('allows forward movement', () => {
    expect(shouldUpdateStatus(DeliveryStatus.Registered, DeliveryStatus.PickedUp)).toBe(true);
    expect(shouldUpdateStatus(DeliveryStatus.PickedUp, DeliveryStatus.InTransitIn)).toBe(true);
    expect(shouldUpdateStatus(DeliveryStatus.InTransitIn, DeliveryStatus.Delivered)).toBe(true);
  });

  it('rejects backward movement', () => {
    expect(shouldUpdateStatus(DeliveryStatus.OutForDelivery, DeliveryStatus.Registered)).toBe(false);
    expect(shouldUpdateStatus(DeliveryStatus.Delivered, DeliveryStatus.OutForDelivery)).toBe(false);
  });

  it('rejects same status', () => {
    expect(shouldUpdateStatus(DeliveryStatus.Registered, DeliveryStatus.Registered)).toBe(false);
  });
});

describe('resolveNewStatus', () => {
  it('updates when new status is forward', () => {
    expect(resolveNewStatus(DeliveryStatus.Registered, 'AT_PICKUP')).toBe(DeliveryStatus.PickedUp);
  });

  it('keeps current status when mapped is null', () => {
    expect(resolveNewStatus(DeliveryStatus.InTransitIn, 'ATTEMPT_FAIL')).toBe(DeliveryStatus.InTransitIn);
  });

  it('keeps current status when new status is backward', () => {
    expect(resolveNewStatus(DeliveryStatus.OutForDelivery, 'AT_PICKUP')).toBe(DeliveryStatus.OutForDelivery);
  });

  it('handles full delivery lifecycle (5단계 = 택배사 코드)', () => {
    let status = DeliveryStatus.Registered;
    status = resolveNewStatus(status, 'AT_PICKUP');
    expect(status).toBe(DeliveryStatus.PickedUp);

    status = resolveNewStatus(status, 'IN_TRANSIT', '대전HUB 상차');
    expect(status).toBe(DeliveryStatus.InTransitIn);

    // 하차 이벤트가 와도 세분화 없이 간선 유지
    status = resolveNewStatus(status, 'IN_TRANSIT', '서울HUB 하차');
    expect(status).toBe(DeliveryStatus.InTransitIn);

    status = resolveNewStatus(status, 'OUT_FOR_DELIVERY', '배송중');
    expect(status).toBe(DeliveryStatus.OutForDelivery);

    status = resolveNewStatus(status, 'DELIVERED', '배송완료');
    expect(status).toBe(DeliveryStatus.Delivered);
  });

  it('never goes backward even with valid codes', () => {
    let status = DeliveryStatus.OutForDelivery;
    status = resolveNewStatus(status, 'IN_TRANSIT', '상차');
    expect(status).toBe(DeliveryStatus.OutForDelivery);

    status = resolveNewStatus(status, 'AT_PICKUP');
    expect(status).toBe(DeliveryStatus.OutForDelivery);
  });
});

describe('mapTrack17Status (17TRACK 해외 코드)', () => {
  it('maps InfoReceived to registered', () => {
    expect(mapTrack17Status('InfoReceived')).toBe(DeliveryStatus.Registered);
  });

  it('folds InTransit (통관 포함) into inTransitIn', () => {
    expect(mapTrack17Status('InTransit')).toBe(DeliveryStatus.InTransitIn);
    expect(mapTrack17Status('InTransit', 'Customs clearance in progress')).toBe(DeliveryStatus.InTransitIn);
  });

  it('treats AvailableForPickup same as OutForDelivery', () => {
    expect(mapTrack17Status('AvailableForPickup')).toBe(DeliveryStatus.OutForDelivery);
    expect(mapTrack17Status('OutForDelivery')).toBe(DeliveryStatus.OutForDelivery);
  });

  it('maps Delivered to delivered', () => {
    expect(mapTrack17Status('Delivered')).toBe(DeliveryStatus.Delivered);
  });

  it('returns null for non-progress states (전진 없음)', () => {
    expect(mapTrack17Status('NotFound')).toBeNull();
    expect(mapTrack17Status('Expired')).toBeNull();
    expect(mapTrack17Status('DeliveryFailure')).toBeNull();
    expect(mapTrack17Status('Exception')).toBeNull();
  });
});

describe('resolveNewStatus — provider 분기', () => {
  it('uses 17TRACK codes only when provider is track17', () => {
    // 같은 문자열이라도 provider 에 따라 해석이 달라진다
    expect(resolveNewStatus(DeliveryStatus.Registered, 'InTransit', '', 'track17'))
      .toBe(DeliveryStatus.InTransitIn);
    // tracker(기본)에서는 모르는 코드 → 현재 상태 유지
    expect(resolveNewStatus(DeliveryStatus.Registered, 'InTransit'))
      .toBe(DeliveryStatus.Registered);
  });

  it('never moves backwards for 17TRACK either', () => {
    expect(resolveNewStatus(DeliveryStatus.OutForDelivery, 'InTransit', '', 'track17'))
      .toBe(DeliveryStatus.OutForDelivery);
  });

  it('keeps current status on DeliveryFailure (배송실패는 전진 아님)', () => {
    expect(resolveNewStatus(DeliveryStatus.OutForDelivery, 'DeliveryFailure', '', 'track17'))
      .toBe(DeliveryStatus.OutForDelivery);
  });
});
