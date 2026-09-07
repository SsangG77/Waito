import { describe, it, expect } from 'vitest';
import { parseEventCoords } from '../src/services/track17Api.js';

describe('parseEventCoords (17TRACK 이벤트 좌표)', () => {
  it('정상 좌표를 읽는다', () => {
    const event = { address: { coordinates: { latitude: '22.547', longitude: '114.085947' } } };
    expect(parseEventCoords(event)).toEqual({ lat: 22.547, lon: 114.085947 });
  });

  it('위도·경도가 뒤바뀐 응답을 되돌린다 (문서 예시에 실제로 있음)', () => {
    // 위도 104 는 존재할 수 없음 → 서로 바꿔야 유효
    const event = { address: { coordinates: { latitude: '104.195397', longitude: '35.86166' } } };
    expect(parseEventCoords(event)).toEqual({ lat: 35.86166, lon: 104.195397 });
  });

  it('둘 다 범위를 벗어나면 버린다', () => {
    const event = { address: { coordinates: { latitude: '999', longitude: '999' } } };
    expect(parseEventCoords(event)).toBeNull();
  });

  it('좌표가 비어 있으면 null', () => {
    expect(parseEventCoords({ address: { coordinates: { latitude: null, longitude: null } } })).toBeNull();
    expect(parseEventCoords({ address: null })).toBeNull();
    expect(parseEventCoords({})).toBeNull();
  });
});
