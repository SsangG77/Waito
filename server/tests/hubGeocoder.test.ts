import { describe, it, expect } from 'vitest';
import { parseKakaoCoords, searchVariants, isInKorea } from '../src/services/hubGeocoder.js';

describe('parseKakaoCoords (x=경도, y=위도)', () => {
  it('첫 장소의 x/y 를 경도/위도로 읽는다', () => {
    const body = { documents: [{ x: '127.4890', y: '36.3504', place_name: '대전HUB' }] };
    expect(parseKakaoCoords(body)).toEqual({ lat: 36.3504, lon: 127.489 });
  });

  it('결과가 없으면 null', () => {
    expect(parseKakaoCoords({ documents: [] })).toBeNull();
    expect(parseKakaoCoords({})).toBeNull();
  });

  it('x/y 가 뒤바뀐 값은 한반도 범위 밖이라 버린다', () => {
    // 위경도를 반대로 넣은 응답 — 위도 127 은 존재할 수 없는 값
    expect(parseKakaoCoords({ documents: [{ x: '36.3504', y: '127.4890' }] })).toBeNull();
  });

  it('숫자가 아니면 null', () => {
    expect(parseKakaoCoords({ documents: [{ x: 'abc', y: '36.35' }] })).toBeNull();
  });
});

describe('searchVariants (허브 접미사 제거 재시도)', () => {
  it('접미사가 있으면 원문 + 제거본 2개', () => {
    expect(searchVariants('옥천HUB')).toEqual(['옥천HUB', '옥천']);
    expect(searchVariants('대전 터미널')).toEqual(['대전 터미널', '대전']);
  });

  it('접미사가 없으면 원문 하나만', () => {
    expect(searchVariants('서울강남')).toEqual(['서울강남']);
  });
});

describe('isInKorea', () => {
  it('서울 좌표는 통과', () => {
    expect(isInKorea({ lat: 37.5665, lon: 126.978 })).toBe(true);
  });

  it('도쿄 좌표는 거부', () => {
    expect(isInKorea({ lat: 35.6762, lon: 139.6503 })).toBe(false);
  });
});
