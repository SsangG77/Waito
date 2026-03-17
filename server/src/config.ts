import dotenv from 'dotenv';
import fs from 'fs';
import path from 'path';

dotenv.config();

export const config = {
  port: parseInt(process.env.PORT || '3000', 10),

  tracker: {
    apiUrl: process.env.TRACKER_API_URL || 'https://apis.tracker.delivery/graphql',
    clientId: process.env.TRACKER_CLIENT_ID || '',
    clientSecret: process.env.TRACKER_CLIENT_SECRET || '',
    credentialIssuedAt: process.env.TRACKER_CREDENTIAL_ISSUED_AT || '',
    credentialLifetimeDays: 21,
  },

  apns: {
    keyId: process.env.APNS_KEY_ID || '',
    teamId: process.env.APNS_TEAM_ID || '',
    keyPath: process.env.APNS_KEY_PATH || './certs/AuthKey.p8',
    bundleId: process.env.APNS_BUNDLE_ID || 'com.sangjin.waito',
  },

  webhookBaseUrl: process.env.WEBHOOK_BASE_URL || 'http://localhost:3000',

  admin: {
    secret: process.env.ADMIN_SECRET || 'waito-admin',
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
