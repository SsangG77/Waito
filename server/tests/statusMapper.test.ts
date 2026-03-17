import { describe, it, expect } from 'vitest';
import { mapTrackerStatus, shouldUpdateStatus, resolveNewStatus } from '../src/services/statusMapper.js';
import { DeliveryStatus } from '../src/types/delivery.js';

describe('mapTrackerStatus', () => {
  it('maps INFORMATION_RECEIVED to registered', () => {
    expect(mapTrackerStatus('INFORMATION_RECEIVED')).toBe(DeliveryStatus.Registered);
  });

  it('maps AT_PICKUP to pickedUp', () => {
    expect(mapTrackerStatus('AT_PICKUP')).toBe(DeliveryStatus.PickedUp);
  });

  it('maps IN_TRANSIT default to inTransitIn', () => {
    expect(mapTrackerStatus('IN_TRANSIT')).toBe(DeliveryStatus.InTransitIn);
  });

  it('maps IN_TRANSIT with 상차 keyword to inTransitIn', () => {
    expect(mapTrackerStatus('IN_TRANSIT', '대전HUB 상차')).toBe(DeliveryStatus.InTransitIn);
  });

  it('maps IN_TRANSIT with 집하 keyword to inTransitIn', () => {
    expect(mapTrackerStatus('IN_TRANSIT', '집하처리')).toBe(DeliveryStatus.InTransitIn);
  });

  it('maps IN_TRANSIT with 발송 keyword to inTransitIn', () => {
    expect(mapTrackerStatus('IN_TRANSIT', '발송')).toBe(DeliveryStatus.InTransitIn);
  });

  it('maps IN_TRANSIT with 하차 keyword to inTransitOut', () => {
    expect(mapTrackerStatus('IN_TRANSIT', '서울HUB 하차')).toBe(DeliveryStatus.InTransitOut);
  });

  it('maps IN_TRANSIT with 도착 keyword to inTransitOut', () => {
    expect(mapTrackerStatus('IN_TRANSIT', '배송지 도착')).toBe(DeliveryStatus.InTransitOut);
  });

  it('maps IN_TRANSIT with 배달준비 keyword to inTransitOut', () => {
    expect(mapTrackerStatus('IN_TRANSIT', '배달준비중')).toBe(DeliveryStatus.InTransitOut);
  });

  it('maps OUT_FOR_DELIVERY to outForDelivery', () => {
    expect(mapTrackerStatus('OUT_FOR_DELIVERY')).toBe(DeliveryStatus.OutForDelivery);
  });

  it('maps OUT_FOR_DELIVERY with 배송중 to delivering', () => {
    expect(mapTrackerStatus('OUT_FOR_DELIVERY', '배송중')).toBe(DeliveryStatus.Delivering);
  });

  it('maps OUT_FOR_DELIVERY with 배달중 to delivering', () => {
    expect(mapTrackerStatus('OUT_FOR_DELIVERY', '배달중입니다')).toBe(DeliveryStatus.Delivering);
  });

  it('maps DELIVERED to delivered', () => {
    expect(mapTrackerStatus('DELIVERED')).toBe(DeliveryStatus.Delivered);
  });

  it('returns null for ATTEMPT_FAIL', () => {
    expect(mapTrackerStatus('ATTEMPT_FAIL')).toBeNull();
  });

  it('returns null for EXCEPTION', () => {
    expect(mapTrackerStatus('EXCEPTION')).toBeNull();
  });

  it('returns null for UNKNOWN', () => {
    expect(mapTrackerStatus('UNKNOWN')).toBeNull();
  });

  it('returns null for unrecognized codes', () => {
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
    expect(shouldUpdateStatus(DeliveryStatus.InTransitOut, DeliveryStatus.Registered)).toBe(false);
    expect(shouldUpdateStatus(DeliveryStatus.Delivering, DeliveryStatus.OutForDelivery)).toBe(false);
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

  it('handles full delivery lifecycle', () => {
    let status = DeliveryStatus.Registered;
    status = resolveNewStatus(status, 'AT_PICKUP', '집화완료');
    expect(status).toBe(DeliveryStatus.PickedUp);

    status = resolveNewStatus(status, 'IN_TRANSIT', '대전HUB 상차');
    expect(status).toBe(DeliveryStatus.InTransitIn);

    status = resolveNewStatus(status, 'IN_TRANSIT', '서울HUB 하차');
    expect(status).toBe(DeliveryStatus.InTransitOut);

    status = resolveNewStatus(status, 'OUT_FOR_DELIVERY', '배송출발');
    expect(status).toBe(DeliveryStatus.OutForDelivery);

    status = resolveNewStatus(status, 'OUT_FOR_DELIVERY', '배송중');
    expect(status).toBe(DeliveryStatus.Delivering);

    status = resolveNewStatus(status, 'DELIVERED', '배송완료');
    expect(status).toBe(DeliveryStatus.Delivered);
  });

  it('never goes backward even with valid codes', () => {
    let status = DeliveryStatus.Delivering;
    status = resolveNewStatus(status, 'IN_TRANSIT', '상차');
    expect(status).toBe(DeliveryStatus.Delivering);

    status = resolveNewStatus(status, 'AT_PICKUP');
    expect(status).toBe(DeliveryStatus.Delivering);
  });
});
