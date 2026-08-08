export enum DeliveryStatus {
  Registered = 'registered',
  PickedUp = 'pickedUp',
  InTransitIn = 'inTransitIn',
  InTransitOut = 'inTransitOut',
  OutForDelivery = 'outForDelivery',
  Delivering = 'delivering',
  Delivered = 'delivered',
}

export const STATUS_T_VALUES: Record<DeliveryStatus, number> = {
  [DeliveryStatus.Registered]: 0.05,
  [DeliveryStatus.PickedUp]: 0.2,
  [DeliveryStatus.InTransitIn]: 0.35,
  [DeliveryStatus.InTransitOut]: 0.5,
  [DeliveryStatus.OutForDelivery]: 0.65,
  [DeliveryStatus.Delivering]: 0.8,
  [DeliveryStatus.Delivered]: 0.95,
};

export interface Carrier {
  id: string;
  name: string;
  trackerId: string;
}

export const CARRIERS: Carrier[] = [
  { id: 'cj', name: 'CJ대한통운', trackerId: 'kr.cjlogistics' },
  { id: 'hanjin', name: '한진택배', trackerId: 'kr.hanjin' },
  { id: 'lotte', name: '롯데택배', trackerId: 'kr.lotte' },
  { id: 'epost', name: '우체국택배', trackerId: 'kr.epost' },
  { id: 'logen', name: '로젠택배', trackerId: 'kr.logen' },
  { id: 'coupang', name: '쿠팡', trackerId: 'kr.coupangls' },
];

export interface Tracking {
  id: number;
  deviceId: number;
  carrierId: string;
  trackingNumber: string;
  itemName: string;
  currentStatus: DeliveryStatus;
  currentTValue: number;
  carrierName: string;
  estimatedDelivery: string | null;
  liveActivityPushToken: string | null;
  webhookId: string | null;
  webhookExpiresAt: string | null;
  lastPolledAt: string | null;
  lastEventTime: string | null;
  createdAt: string;
  updatedAt: string;
  deliveredAt: string | null;
}

export interface TrackingEvent {
  id: number;
  trackingId: number;
  trackerStatus: string;
  mappedStatus: DeliveryStatus;
  description: string;
  eventTime: string;
  location: string | null;
  createdAt: string;
}

export interface TrackerDeliveryEvent {
  time: string;
  status: { code: string };
  description: string;
  // tracker.delivery Location 오브젝트 — 이름(허브명 등)만 사용. 좌표/우편번호는 API 가 이름 외 제공 안 함.
  location?: { name?: string } | null;
}

export interface TrackerDeliveryResponse {
  track: {
    lastEvent: {
      time: string;
      status: { code: string };
    } | null;
    events: {
      edges: Array<{
        node: TrackerDeliveryEvent;
      }>;
    };
  };
}
