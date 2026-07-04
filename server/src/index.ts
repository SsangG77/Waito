import express from 'express';
import { config } from './config.js';
import { initDb, closeDb, getDb } from './db/database.js';
import { startPollingScheduler } from './services/pollingService.js';
import { TEST_TRACKING_NUMBER } from './services/trackerApi.js';
import { startCredentialMonitor, getCredentialHealth } from './services/credentialMonitor.js';
import devicesRouter from './routes/devices.js';
import trackingsRouter from './routes/trackings.js';
import carriersRouter from './routes/carriers.js';
import webhooksRouter from './routes/webhooks.js';
import adminRouter from './routes/admin.js';
import legalRouter from './routes/legal.js';

const app = express();

app.use(express.json());

// Routes
app.use('/api/devices', devicesRouter);
app.use('/api/trackings', trackingsRouter);
app.use('/api/carriers', carriersRouter);
app.use('/webhooks', webhooksRouter);
app.use('/admin', adminRouter);
// 개인정보처리방침 / 이용약관(EULA) 정적 페이지 — 앱 구독 화면·ASC 메타데이터에서 링크
app.use('/', legalRouter);

// Health check (credential 상태 포함)
app.get('/health', (_req, res) => {
  const credential = getCredentialHealth();
  res.json({
    status: credential.isValid ? 'ok' : 'degraded',
    timestamp: new Date().toISOString(),
    credential,
  });
});

// Initialize
initDb();

// 유령 테스트 택배 정리 — 앱에서 지운 뒤 비활성(apns_token 없는) 구설치/desync 디바이스에 남아
// 계속 푸시하던 test970719 행을 부팅 시 제거.
getDb()
  .prepare(
    `DELETE FROM trackings WHERE tracking_number = ?
       AND device_id IN (SELECT id FROM devices WHERE apns_token IS NULL)`,
  )
  .run(TEST_TRACKING_NUMBER);

startCredentialMonitor();
startPollingScheduler();

const server = app.listen(config.port, () => {
  console.log(`Waito server running on port ${config.port}`);
});

// Graceful shutdown
process.on('SIGTERM', () => {
  console.log('SIGTERM received, shutting down...');
  server.close(() => {
    closeDb();
    process.exit(0);
  });
});

process.on('SIGINT', () => {
  console.log('SIGINT received, shutting down...');
  server.close(() => {
    closeDb();
    process.exit(0);
  });
});

export default app;
