import cron from 'node-cron';
import { config } from '../config.js';

export interface CredentialHealth {
  isValid: boolean;
  issuedAt: string | null;
  expiresAt: string | null;
  daysRemaining: number | null;
  warning: string | null;
}

let apiExpired = false;

/**
 * API 호출에서 401을 받았을 때 호출. credential 만료로 간주한다.
 */
export function markCredentialExpired(): void {
  if (!apiExpired) {
    console.error('[Credential] ⚠️  tracker.delivery credential이 만료되었습니다!');
    console.error('[Credential] tracker.delivery 웹 콘솔에서 credential을 갱신하고 .env를 업데이트하세요.');
    console.error('[Credential] 갱신 후 서버를 재시작하세요.');
  }
  apiExpired = true;
}

/**
 * credential이 만료 상태인지 확인한다. 만료되면 API 호출을 건너뛴다.
 */
export function isCredentialExpired(): boolean {
  return apiExpired;
}

/**
 * credential 갱신 후 만료 플래그를 초기화한다.
 */
export function resetCredentialExpired(): void {
  apiExpired = false;
}

/**
 * .env의 발급일 기준으로 credential 상태를 계산한다.
 */
export function getCredentialHealth(): CredentialHealth {
  if (apiExpired) {
    return {
      isValid: false,
      issuedAt: config.tracker.credentialIssuedAt || null,
      expiresAt: null,
      daysRemaining: 0,
      warning: 'credential이 만료되었습니다. tracker.delivery 웹 콘솔에서 갱신하세요.',
    };
  }

  const issuedAt = config.tracker.credentialIssuedAt;
  if (!issuedAt) {
    return {
      isValid: true,
      issuedAt: null,
      expiresAt: null,
      daysRemaining: null,
      warning: 'TRACKER_CREDENTIAL_ISSUED_AT이 설정되지 않았습니다. 만료일을 추적할 수 없습니다.',
    };
  }

  const issued = new Date(issuedAt);
  if (isNaN(issued.getTime())) {
    return {
      isValid: true,
      issuedAt,
      expiresAt: null,
      daysRemaining: null,
      warning: 'TRACKER_CREDENTIAL_ISSUED_AT 날짜 형식이 잘못되었습니다 (YYYY-MM-DD).',
    };
  }

  const expires = new Date(issued);
  expires.setDate(expires.getDate() + config.tracker.credentialLifetimeDays);

  const now = new Date();
  const msRemaining = expires.getTime() - now.getTime();
  const daysRemaining = Math.ceil(msRemaining / (1000 * 60 * 60 * 24));

  let warning: string | null = null;
  if (daysRemaining <= 0) {
    warning = 'credential이 만료되었을 수 있습니다! tracker.delivery 웹 콘솔에서 갱신하세요.';
  } else if (daysRemaining <= 1) {
    warning = `credential이 내일 만료됩니다! (D-${daysRemaining})`;
  } else if (daysRemaining <= 3) {
    warning = `credential 만료 ${daysRemaining}일 전입니다. 곧 갱신하세요.`;
  }

  return {
    isValid: daysRemaining > 0,
    issuedAt,
    expiresAt: expires.toISOString().split('T')[0],
    daysRemaining: Math.max(0, daysRemaining),
    warning,
  };
}

/**
 * 매일 오전 9시에 credential 만료 임박 여부를 체크하고 경고 로그를 남긴다.
 */
export function startCredentialMonitor(): void {
  // 서버 시작 시 즉시 1회 체크
  const health = getCredentialHealth();
  if (health.warning) {
    console.warn(`[Credential] ${health.warning}`);
  }
  if (health.daysRemaining !== null) {
    console.log(`[Credential] 만료까지 ${health.daysRemaining}일 남음 (만료일: ${health.expiresAt})`);
  }

  // 매일 오전 9시 체크
  cron.schedule('0 9 * * *', () => {
    const h = getCredentialHealth();
    if (h.warning) {
      console.warn(`[Credential] ${h.warning}`);
    }
  });
}
