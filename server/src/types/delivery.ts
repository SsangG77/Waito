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

/**
 * 조회 제공자.
 * - tracker: tracker.delivery(GraphQL). 국내 전용, 무료지만 credential 이 21일마다 만료.
 * - track17: 17TRACK(REST). 해외용. 운송장 등록당 과금이라 조회를 자주 해도 비용이 늘지 않는다.
 *
 * 17TRACK 에 국내 6사도 있어 전면 교체가 가능하지만, 지금 규모(월 15건)에서는
 * 무료 quota 를 국내 물량에 태우면 금방 소진돼 국내는 tracker 를 유지한다.
 */
export type CarrierProvider = 'tracker' | 'track17';

export interface Carrier {
  id: string;
  name: string;
  /** 제공자별 택배사 식별자. tracker 는 'kr.cjlogistics' 형식, track17 은 숫자 key 문자열. */
  trackerId: string;
  provider: CarrierProvider;
  /** 해외 택배사 여부 — 앱에서 국내/해외 그룹을 나눠 보여줄 때 쓴다. */
  international?: boolean;
}

export const CARRIERS: Carrier[] = [
  // 국내 — tracker.delivery
  { id: 'cj', name: 'CJ대한통운', trackerId: 'kr.cjlogistics', provider: 'tracker' },
  { id: 'hanjin', name: '한진택배', trackerId: 'kr.hanjin', provider: 'tracker' },
  { id: 'lotte', name: '롯데택배', trackerId: 'kr.lotte', provider: 'tracker' },
  { id: 'epost', name: '우체국택배', trackerId: 'kr.epost', provider: 'tracker' },
  { id: 'logen', name: '로젠택배', trackerId: 'kr.logen', provider: 'tracker' },
  { id: 'coupang', name: '쿠팡', trackerId: 'kr.coupangls', provider: 'tracker' },

  // 해외 — 17TRACK. trackerId 는 공식 캐리어 목록(apicarrier.all.csv)의 key.
  { id: 'cainiao', name: 'Cainiao (알리·테무)', trackerId: '190271', provider: 'track17', international: true },
  { id: 'dhl', name: 'DHL', trackerId: '101266', provider: 'track17', international: true },
  { id: 'fedex', name: 'FedEx', trackerId: '100003', provider: 'track17', international: true },
  { id: 'ups', name: 'UPS', trackerId: '100002', provider: 'track17', international: true },
  { id: 'usps', name: 'USPS', trackerId: '21051', provider: 'track17', international: true },
  { id: 'japanpost', name: 'Japan Post', trackerId: '10021', provider: 'track17', international: true },
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
