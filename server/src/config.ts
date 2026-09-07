import dotenv from 'dotenv';
import fs from 'fs';
import path from 'path';

dotenv.config();

/** 운영 서버 실주소. .env 가 비었거나 자리표시자면 이 값으로 동작한다. */
const PUBLIC_URL_FALLBACK = 'http://158.247.223.154:3001';

function resolvePublicUrl(): string {
  const raw = (process.env.WEBHOOK_BASE_URL || '').trim();
  if (!raw || raw.includes('your-server')) return PUBLIC_URL_FALLBACK;
  return raw.replace(/\/+$/, '');
}

export const config = {
  port: parseInt(process.env.PORT || '3000', 10),

  tracker: {
    apiUrl: process.env.TRACKER_API_URL || 'https://apis.tracker.delivery/graphql',
    clientId: process.env.TRACKER_CLIENT_ID || '',
    clientSecret: process.env.TRACKER_CLIENT_SECRET || '',
    credentialIssuedAt: process.env.TRACKER_CREDENTIAL_ISSUED_AT || '',
    credentialLifetimeDays: 21,
  },

  // 17TRACK — 해외 택배사 조회. 키가 없으면 해외 택배 등록·폴링을 graceful skip 한다.
  // 과금은 운송장 등록당 1건이고 이후 조회는 무과금이라 폴링 주기와 무관하다.
  track17: {
    apiUrl: process.env.TRACK17_API_URL || 'https://api.17track.net/track/v2.2',
    apiKey: process.env.TRACK17_API_KEY || '',
  },

  apns: {
    keyId: process.env.APNS_KEY_ID || '',
    teamId: process.env.APNS_TEAM_ID || '',
    keyPath: process.env.APNS_KEY_PATH || './certs/AuthKey.p8',
    // ⚠️ APNs apns-topic = 앱 번들 ID(대소문자까지 정확히). 앱: com.sangjin.Waito.
    // 고정값으로 박는다 — env(APNS_BUNDLE_ID)로 덮어쓰지 않음.
    // (운영 .env 에 소문자 com.sangjin.waito 가 설정돼 TopicDisallowed 로 모든 푸시가 거부된 이력 있음)
    bundleId: 'com.sangjin.Waito',
    // 기본은 sandbox(개발). 프로덕션 APNs 사용 시 APNS_PRODUCTION=true
    production: process.env.APNS_PRODUCTION === 'true',
  },

  // 운영 서버 공개 주소. webhook 콜백 URL 과 이메일 속 관리자 링크가 이 값을 쓴다.
  // ⚠️ .env.example 의 자리표시자(your-server.com)가 그대로 남으면 webhook 이 죽고
  //    이메일 버튼도 없는 도메인으로 간다 → 자리표시자면 실제 운영 주소로 되돌린다.
  webhookBaseUrl: resolvePublicUrl(),

  admin: {
    secret: process.env.ADMIN_SECRET || 'waito-admin',
  },

  // credential 만료 임박 등 운영 알림 이메일 (Resend HTTP API 사용, 키 없으면 비활성)
  alert: {
    resendApiKey: process.env.RESEND_API_KEY || '',
    emailTo: process.env.ALERT_EMAIL_TO || '',
    emailFrom: process.env.ALERT_EMAIL_FROM || 'Waito <onboarding@resend.dev>',
  },
};

/**
 * tracker credential을 런타임에 갱신하고 .env 파일도 업데이트한다.
 */
export function updateTrackerCredentials(clientId: string, clientSecret: string): void {
  config.tracker.clientId = clientId;
  config.tracker.clientSecret = clientSecret;
  config.tracker.credentialIssuedAt = new Date().toISOString().split('T')[0];

  // .env 파일 업데이트
  const envPath = path.join(process.cwd(), '.env');
  let envContent = '';
  try {
    envContent = fs.readFileSync(envPath, 'utf-8');
  } catch {
    // .env가 없으면 새로 생성
  }

  const updates: Record<string, string> = {
    TRACKER_CLIENT_ID: clientId,
    TRACKER_CLIENT_SECRET: clientSecret,
    TRACKER_CREDENTIAL_ISSUED_AT: config.tracker.credentialIssuedAt,
  };

  for (const [key, value] of Object.entries(updates)) {
    const regex = new RegExp(`^${key}=.*$`, 'm');
    if (regex.test(envContent)) {
      envContent = envContent.replace(regex, `${key}=${value}`);
    } else {
      envContent += `\n${key}=${value}`;
    }
  }

  fs.writeFileSync(envPath, envContent.trim() + '\n', 'utf-8');
}
