import { describe, it, expect } from 'vitest';
import { mapTrackerStatus, shouldUpdateStatus, resolveNewStatus } from '../src/services/statusMapper.js';
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
