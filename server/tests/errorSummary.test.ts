import { describe, it, expect } from 'vitest';
import { ClientError } from 'graphql-request';
import { errorSummary } from '../src/services/trackerApi.js';

describe('errorSummary', () => {
  it('GraphQL 오류는 응답 JSON 없이 상태 코드와 메시지만 한 줄로 남긴다', () => {
    const big = 'x'.repeat(5000);
    const err = new ClientError(
      { status: 200, headers: new Headers(), body: big, errors: [{ message: 'Not found', extensions: { code: 'NOT_FOUND' } } as any] } as any,
      { query: big, variables: { trackingNumber: '123' } } as any,
    );
    const s = errorSummary(err);
    expect(s).toBe('GraphQL HTTP 200 NOT_FOUND Not found');
  });

  it('일반 오류는 첫 줄만, 300자 이하', () => {
    expect(errorSummary(new Error('boom\nstack...'))).toBe('boom');
    expect(errorSummary('y'.repeat(1000)).length).toBe(300);
  });
});
