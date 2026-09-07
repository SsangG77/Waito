import { describe, it, expect, vi, beforeEach } from 'vitest';
import fs from 'fs';
import os from 'os';
import path from 'path';

// 발급일 기록 파일을 임시 경로로 돌려 실제 서버 파일을 건드리지 않는다.
const STATE_PATH = path.join(os.tmpdir(), `waito-credential-state-${process.pid}.json`);
process.env.CREDENTIAL_STATE_PATH = STATE_PATH;

// config를 모킹해서 발급일을 제어한다
vi.mock('../src/config.js', () => ({
  config: {
    tracker: {
      clientId: 'client-id',
      clientSecret: 'secret-v1',
      credentialIssuedAt: '',
      credentialLifetimeDays: 21,
    },
  },
}));

import { config } from '../src/config.js';
import { getCredentialHealth, markCredentialExpired, isCredentialExpired } from '../src/services/credentialMonitor.js';

// 타입 단언으로 mutable하게 만들기
const mutableConfig = config as {
  tracker: {
    clientId: string;
    clientSecret: string;
    credentialIssuedAt: string;
    credentialLifetimeDays: number;
  };
};

function daysAgo(n: number): string {
  const d = new Date();
  d.setDate(d.getDate() - n);
  return d.toISOString().split('T')[0];
}

describe('credentialMonitor', () => {
  beforeEach(() => {
    // 기록을 지워 "이 credential 을 처음 보는" 상태로 되돌린다 → .env 발급일을 그대로 쓴다
    fs.rmSync(STATE_PATH, { force: true });
    mutableConfig.tracker.clientSecret = 'secret-v1';
  });

  describe('getCredentialHealth', () => {
    it('.env 발급일이 없으면 오늘부터 세기 시작한다', () => {
      mutableConfig.tracker.credentialIssuedAt = '';
      const health = getCredentialHealth();
      expect(health.isValid).toBe(true);
      expect(health.daysRemaining).toBe(21);
      expect(health.warning).toBeNull();
    });

    it('.env 발급일 형식이 깨져 있어도 오늘부터 세기 시작한다', () => {
      mutableConfig.tracker.credentialIssuedAt = 'not-a-date';
      expect(getCredentialHealth().daysRemaining).toBe(21);
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

    it('키가 그대로면 기록된 발급일을 계속 쓴다 (.env 날짜가 바뀌어도 무시)', () => {
      mutableConfig.tracker.credentialIssuedAt = daysAgo(5);
      expect(getCredentialHealth().daysRemaining).toBe(16);

      // 누군가 .env 날짜만 오늘로 바꿔놔도 키가 같으면 처음 본 날짜를 유지한다
      mutableConfig.tracker.credentialIssuedAt = daysAgo(0);
      expect(getCredentialHealth().daysRemaining).toBe(16);
    });

    it('키가 바뀌면 그날을 발급일로 새로 기록한다', () => {
      mutableConfig.tracker.credentialIssuedAt = '2026-03-17'; // 예시 파일에 굳어 있던 값
      expect(getCredentialHealth().daysRemaining).toBe(0);

      mutableConfig.tracker.clientSecret = 'secret-v2'; // 콘솔에서 재발급
      const health = getCredentialHealth();
      expect(health.issuedAt).toBe(new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Seoul' }));
      expect(health.daysRemaining).toBe(21);
      expect(health.warning).toBeNull();
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
