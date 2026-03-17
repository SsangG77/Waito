import express from 'express';
import { config } from './config.js';
import { initDb, closeDb } from './db/database.js';
import { startPollingScheduler } from './services/pollingService.js';
import { startCredentialMonitor, getCredentialHealth } from './services/credentialMonitor.js';
import devicesRouter from './routes/devices.js';
import trackingsRouter from './routes/trackings.js';
import carriersRouter from './routes/carriers.js';
import webhooksRouter from './routes/webhooks.js';
import adminRouter from './routes/admin.js';

const app = express();

app.use(express.json());

// Routes
app.use('/api/devices', devicesRouter);
app.use('/api/trackings', trackingsRouter);
app.use('/api/carriers', carriersRouter);
app.use('/webhooks', webhooksRouter);
app.use('/admin', adminRouter);

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
