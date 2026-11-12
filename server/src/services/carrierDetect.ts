import { trackPackage } from './trackerApi.js';
import { detectCarrier17 } from './track17Api.js';
import { CARRIERS, type Carrier } from '../types/delivery.js';

/**
 * 운송장 번호만으로 택배사를 감지한다 (carrierId='auto', 그리고 조회 안 되는 번호 다시 찾기).
 * 1) 국내: tracker.delivery 를 CARRIERS 순서대로 조회 — 이벤트가 나오는 택배사 채택.
 *    (한국 운송장은 자릿수가 12~13자리로 겹쳐 패턴 판별이 불가능 → 실조회가 정답)
 * 2) 전부 실패 시: 17TRACK 자동 감지(등록 시 carrier 생략) → 우리 해외 CARRIERS 와 매핑.
 *    지원 목록 밖 택배사로 감지되면 null (quota 1건 소모는 감수 — 드묾).
 */
export async function detectCarrier(trackingNumber: string): Promise<Carrier | null> {
  for (const candidate of CARRIERS.filter(c => c.provider === 'tracker')) {
    try {
      const result = await trackPackage(candidate.trackerId, trackingNumber);
      if (result.track?.lastEvent) return candidate;
    } catch {
      // NOT_FOUND·오류 → 다음 후보
    }
  }

  const key = await detectCarrier17(trackingNumber);
  if (key) {
    const matched = CARRIERS.find(c => c.provider === 'track17' && c.trackerId === key);
    if (matched) return matched;
    console.warn(`[Detect] 17TRACK 감지 결과가 지원 목록 밖 (carrier key=${key})`);
  }
  return null;
}
