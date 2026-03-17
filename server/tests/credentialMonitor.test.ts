import { describe, it, expect, vi, beforeEach } from 'vitest';

// config를 모킹해서 발급일을 제어한다
vi.mock('../src/config.js', () => ({
  config: {
    tracker: {
      credentialIssuedAt: '',
      credentialLifetimeDays: 21,
    },
  },
}));

import { config } from '../src/config.js';
import { getCredentialHealth, markCredentialExpired, isCredentialExpired } from '../src/services/credentialMonitor.js';

// 타입 단언으로 mutable하게 만들기
const mutableConfig = config as { tracker: { credentialIssuedAt: string; credentialLifetimeDays: number } };

describe('credentialMonitor', () => {
  beforeEach(() => {
    // 각 테스트마다 모듈 상태 초기화를 위해 expired 플래그 리셋은 불가하므로
    // markCredentialExpired 테스트는 마지막에 배치
  });

  describe('getCredentialHealth', () => {
    it('warns when TRACKER_CREDENTIAL_ISSUED_AT is not set', () => {
      mutableConfig.tracker.credentialIssuedAt = '';
      const health = getCredentialHealth();
      expect(health.isValid).toBe(true);
      expect(health.daysRemaining).toBeNull();
      expect(health.warning).toContain('설정되지 않았습니다');
    });

    it('warns for invalid date format', () => {
      mutableConfig.tracker.credentialIssuedAt = 'not-a-date';
      const health = getCredentialHealth();
      expect(health.warning).toContain('날짜 형식');
    });

    it('calculates days remaining correctly', () => {
      // 오늘 발급했으면 21일 남아야 함
      const today = new Date().toISOString().split('T')[0];
      mutableConfig.tracker.credentialIssuedAt = today;
      const health = getCredentialHealth();
      expect(health.isValid).toBe(true);
      expect(health.daysRemaining).toBe(21);
      expect(health.warning).toBeNull();
    });

    it('warns at D-3', () => {
      const daysAgo18 = new Date();
      daysAgo18.setDate(daysAgo18.getDate() - 18);
      mutableConfig.tracker.credentialIssuedAt = daysAgo18.toISOString().split('T')[0];
      const health = getCredentialHealth();
      expect(health.daysRemaining).toBe(3);
      expect(health.warning).toContain('3일 전');
    });

    it('warns at D-1', () => {
      const daysAgo20 = new Date();
      daysAgo20.setDate(daysAgo20.getDate() - 20);
      mutableConfig.tracker.credentialIssuedAt = daysAgo20.toISOString().split('T')[0];
      const health = getCredentialHealth();
      expect(health.daysRemaining).toBe(1);
      expect(health.warning).toContain('내일 만료');
    });

    it('shows expired when past 21 days', () => {
      const daysAgo22 = new Date();
      daysAgo22.setDate(daysAgo22.getDate() - 22);
      mutableConfig.tracker.credentialIssuedAt = daysAgo22.toISOString().split('T')[0];
      const health = getCredentialHealth();
      expect(health.isValid).toBe(false);
      expect(health.daysRemaining).toBe(0);
      expect(health.warning).toContain('만료되었을 수 있습니다');
    });

    it('no warning when plenty of time left', () => {
      const daysAgo5 = new Date();
      daysAgo5.setDate(daysAgo5.getDate() - 5);
      mutableConfig.tracker.credentialIssuedAt = daysAgo5.toISOString().split('T')[0];
      const health = getCredentialHealth();
      expect(health.isValid).toBe(true);
      expect(health.daysRemaining).toBe(16);
      expect(health.warning).toBeNull();
    });
  });
});
