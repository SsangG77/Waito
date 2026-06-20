import cron from 'node-cron';
import fs from 'fs';
import path from 'path';
import { config } from '../config.js';
import { sendAlertEmail } from './emailService.js';

// 같은 날 이메일 중복 발송을 막기 위한 상태 파일(서버 재시작에도 안전)
const ALERT_STATE_PATH = path.join(process.cwd(), 'credential_alert_state.json');

// 만료 임박 알림을 시작할 기준일(일). 이 일수 이하로 남으면 매일 1회 이메일.
const ALERT_THRESHOLD_DAYS = 3;

function todayKST(): string {
  // Asia/Seoul 기준 YYYY-MM-DD
  return new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Seoul' });
}

function alreadyAlertedToday(): boolean {
  try {
    const raw = fs.readFileSync(ALERT_STATE_PATH, 'utf-8');
    const state = JSON.parse(raw) as { lastAlertDate?: string };
    return state.lastAlertDate === todayKST();
  } catch {
    return false;
  }
}

function markAlertedToday(): void {
  try {
    fs.writeFileSync(ALERT_STATE_PATH, JSON.stringify({ lastAlertDate: todayKST() }) + '\n', 'utf-8');
  } catch (err) {
    console.error('[Credential] 알림 상태 저장 실패:', err);
  }
}

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
 * credential 상태를 점검하고, 만료 ALERT_THRESHOLD_DAYS일 이하로 남았으면
 * 운영 이메일을 보낸다(같은 날 1회만).
 */
async function checkAndAlert(): Promise<void> {
  const health = getCredentialHealth();

  if (health.warning) {
    console.warn(`[Credential] ${health.warning}`);
  }
  if (health.daysRemaining !== null) {
    console.log(`[Credential] 만료까지 ${health.daysRemaining}일 남음 (만료일: ${health.expiresAt})`);
  }

  // 만료일 추적 불가(발급일 미설정 등)면 이메일 생략
  if (health.daysRemaining === null) return;

  // 임박(0~3일)일 때만, 하루 1회 발송
  if (health.daysRemaining <= ALERT_THRESHOLD_DAYS) {
    if (alreadyAlertedToday()) return;

    const dday = health.daysRemaining <= 0 ? 'D-day(만료)' : `D-${health.daysRemaining}`;
    // 시크릿을 포함한 '바로 열리는' 갱신 링크 (수신자가 본인 이메일뿐이므로 클릭 한 번 갱신을 우선)
    const renewUrl = `${config.webhookBaseUrl}/admin?secret=${encodeURIComponent(config.admin.secret)}`;
    const subject = `[Waito] tracker.delivery credential 만료 임박 (${dday})`;
    const html = `
      <div style="font-family:sans-serif;line-height:1.6">
        <h2>tracker.delivery credential 갱신 필요</h2>
        <p>택배 조회용 credential이 곧 만료됩니다. 만료되면 모든 택배 상태 조회가 멈춥니다.</p>
        <ul>
          <li><b>남은 기간</b>: ${dday}</li>
          <li><b>만료일</b>: ${health.expiresAt ?? '-'}</li>
          <li><b>발급일</b>: ${health.issuedAt ?? '-'}</li>
        </ul>
        <p>
          1) tracker.delivery 콘솔에서 credential 재발급 →
          2) 아래 버튼(갱신 페이지)에서 새 clientId/clientSecret 입력
        </p>
        <p>
          <a href="${renewUrl}"
             style="display:inline-block;padding:12px 20px;background:#2D7DF6;color:#fff;
                    text-decoration:none;border-radius:8px;font-weight:bold">
            운영 서버 credential 갱신하기 →
          </a>
        </p>
        <p style="font-size:12px;color:#888">버튼이 안 되면 이 주소를 복사해 여세요:<br>${renewUrl}</p>
      </div>`;

    const sent = await sendAlertEmail(subject, html);
    if (sent) markAlertedToday();
  }
}

/**
 * 서버 시작 시 1회 + 매일 오전 9시(KST)에 credential 만료 임박 여부를 체크하고,
 * 만료 3일 전부터 매일 이메일 알림을 보낸다.
 */
export function startCredentialMonitor(): void {
  // 서버 시작 시 즉시 1회 체크
  void checkAndAlert();

  // 매일 오전 9시(Asia/Seoul) 체크
  cron.schedule('0 9 * * *', () => { void checkAndAlert(); }, { timezone: 'Asia/Seoul' });
}
