import { describe, it, expect } from 'vitest';
import { ClientError } from 'graphql-request';
import { isNotFoundTooLong, NOT_FOUND_STOP_HOURS } from '../src/services/pollingService.js';
import { isInvalidTrackingNumberError, isTrackingNotFoundError } from '../src/services/trackerApi.js';

const H = 60 * 60 * 1000;
const created = '2026-11-01 00:00:00';
const createdMs = Date.parse('2026-11-01T00:00:00Z');

describe('조회 안 되는 번호 멈춤 기준', () => {
  it('기준 시간 전에는 멈추지 않음', () => {
    expect(isNotFoundTooLong(created, null, createdMs + (NOT_FOUND_STOP_HOURS - 1) * H)).toBe(false);
  });
  it('기준 시간이 지나면 멈춤', () => {
    expect(isNotFoundTooLong(created, null, createdMs + NOT_FOUND_STOP_HOURS * H)).toBe(true);
  });
  it('한 번이라도 조회된 번호는 멈추지 않음', () => {
    expect(isNotFoundTooLong(created, '2026-11-01T03:00:00Z', createdMs + 999 * H)).toBe(false);
  });
});

function clientError(message: string, code?: string): ClientError {
  return new ClientError(
    { status: 200, errors: [{ message, extensions: code ? { code } : {} }] } as never,
    { query: '' } as never,
  );
}

describe('자릿수 오류 판별', () => {
  it('운영 로그 문구를 자릿수 오류로 봄', () => {
    expect(isInvalidTrackingNumberError(clientError('운송장 번호는 10자리 혹은 12자리입니다.'))).toBe(true);
  });
  it('NOT_FOUND 는 자릿수 오류가 아님', () => {
    const e = clientError('Not found', 'NOT_FOUND');
    expect(isInvalidTrackingNumberError(e)).toBe(false);
    expect(isTrackingNotFoundError(e)).toBe(true);
  });
});
