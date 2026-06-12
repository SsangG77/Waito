import crypto from 'crypto';
import fs from 'fs';
import http2 from 'http2';
import { config } from '../config.js';

/**
 * APNs HTTP/2 + 토큰 기반(JWT ES256) 클라이언트.
 * 외부 패키지 없이 Node 내장 crypto / http2 만 사용한다.
 *
 * ActivityKit push 는 인증서 인증 미지원 → 토큰(JWT) 인증만 사용.
 */

const APNS_HOST = config.apns.production
  ? 'https://api.push.apple.com'
  : 'https://api.sandbox.push.apple.com';

/** Live Activity push 의 apns-topic (일반 alert topic 과 다름) */
export const LIVE_ACTIVITY_TOPIC = `${config.apns.bundleId}.push-type.liveactivity`;

/**
 * APNs 인증에 필요한 설정과 p8 키 파일이 모두 갖춰졌는지.
 * 갖춰지지 않으면 푸시를 건너뛴다(개발 중 키 없음 등).
 */
export function isApnsConfigured(): boolean {
  if (!config.apns.keyId || !config.apns.teamId) return false;
  try {
    return fs.existsSync(config.apns.keyPath);
  } catch {
    return false;
  }
}

// ── JWT (ES256) ─────────────────────────────────────────────

let cachedJwt: { token: string; iat: number } | null = null;

function base64url(input: Buffer | string): string {
  return Buffer.from(input).toString('base64url');
}

/**
 * APNs provider 인증 토큰(JWT) 생성. APNs 는 동일 토큰을 최대 1시간 재사용 허용하며,
 * 너무 자주 새 토큰을 만들면 거부하므로 ~50분간 캐싱한다.
 */
function getProviderToken(): string {
  const now = Math.floor(Date.now() / 1000);
  if (cachedJwt && now - cachedJwt.iat < 3000) {
    return cachedJwt.token;
  }

  const privateKey = fs.readFileSync(config.apns.keyPath, 'utf8');
  const header = base64url(JSON.stringify({ alg: 'ES256', kid: config.apns.keyId, typ: 'JWT' }));
  const payload = base64url(JSON.stringify({ iss: config.apns.teamId, iat: now }));
  const signingInput = `${header}.${payload}`;

  // ES256: ECDSA P-256 + SHA-256, JOSE(r||s) 서명 포맷
  const signature = crypto.sign('SHA256', Buffer.from(signingInput), {
    key: privateKey,
    dsaEncoding: 'ieee-p1363',
  });

  const token = `${signingInput}.${base64url(signature)}`;
  cachedJwt = { token, iat: now };
  return token;
}

// ── 전송 ────────────────────────────────────────────────────

export interface ApnsRequest {
  /** Live Activity 토큰 또는 push-to-start 토큰 (hex 문자열) */
  deviceToken: string;
  /** APNs 페이로드 (aps 키를 포함하는 객체) */
  payload: Record<string, unknown>;
  /** 5(저우선, budget 미차감) 또는 10(즉시) */
  priority?: number;
  /** Unix 초. 0이면 즉시 만료(재시도 안 함) */
  expiration?: number;
}

export interface ApnsResult {
  ok: boolean;
  status: number;
  /** APNs 거부 사유 (BadDeviceToken 등) */
  reason?: string;
  /** 설정 미비 등으로 전송 자체를 건너뛴 경우 */
  skipped?: boolean;
}

/**
 * Live Activity 관련 push(start/update/end)를 APNs 로 전송한다.
 * push-type 은 항상 liveactivity, topic 은 LIVE_ACTIVITY_TOPIC 고정.
 */
export function sendLiveActivityPush(req: ApnsRequest): Promise<ApnsResult> {
  if (!isApnsConfigured()) {
    console.warn('[APNs] 설정/키 미비 — 푸시 건너뜀 (APNS_KEY_ID/TEAM_ID/KEY_PATH 확인)');
    return Promise.resolve({ ok: false, status: 0, skipped: true });
  }

  const body = JSON.stringify(req.payload);

  return new Promise<ApnsResult>((resolve) => {
    let settled = false;
    let client: http2.ClientHttp2Session | undefined;

    // 모든 종료 경로(정상/타임아웃/에러)가 거치는 단일 정리 지점 — 세션 close 보장
    const finish = (r: ApnsResult) => {
      if (settled) return;
      settled = true;
      try { client?.close(); } catch { /* noop */ }
      resolve(r);
    };

    try {
      client = http2.connect(APNS_HOST);
    } catch (err) {
      console.error('[APNs] connect 실패:', err);
      finish({ ok: false, status: 0, reason: 'connect_failed' });
      return;
    }

    client.on('error', (err) => {
      console.error('[APNs] 세션 오류:', err);
      finish({ ok: false, status: 0, reason: 'session_error' });
    });

    let token: string;
    try {
      token = getProviderToken();
    } catch (err) {
      console.error('[APNs] JWT 생성 실패:', err);
      finish({ ok: false, status: 0, reason: 'jwt_error' });
      return;
    }

    const stream = client.request({
      ':method': 'POST',
      ':path': `/3/device/${req.deviceToken}`,
      'authorization': `bearer ${token}`,
      'apns-push-type': 'liveactivity',
      'apns-topic': LIVE_ACTIVITY_TOPIC,
      'apns-priority': String(req.priority ?? 10),
      'apns-expiration': String(req.expiration ?? 0),
      'content-type': 'application/json',
      'content-length': Buffer.byteLength(body),
    });

    stream.setTimeout(10_000, () => finish({ ok: false, status: 0, reason: 'timeout' }));

    let status = 0;
    let data = '';

    stream.on('response', (headers) => {
      status = Number(headers[':status']) || 0;
    });
    stream.on('data', (chunk) => { data += chunk; });
    stream.on('end', () => {
      let reason: string | undefined;
      if (status !== 200 && data) {
        try { reason = JSON.parse(data).reason; } catch { /* noop */ }
      }
      finish({ ok: status === 200, status, reason });
    });
    stream.on('error', (err) => {
      console.error('[APNs] 스트림 오류:', err);
      finish({ ok: false, status: 0, reason: 'stream_error' });
    });

    stream.write(body);
    stream.end();
  });
}
