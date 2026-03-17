import { Router, Request, Response } from 'express';
import { getDb } from '../db/database.js';

const router = Router();

// POST /api/devices/register
router.post('/register', (req: Request, res: Response) => {
  const { deviceToken } = req.body;

  if (!deviceToken || typeof deviceToken !== 'string') {
    res.status(400).json({ error: 'deviceToken is required' });
    return;
  }

  const db = getDb();

  const existing = db.prepare('SELECT id FROM devices WHERE device_token = ?').get(deviceToken) as { id: number } | undefined;

  if (existing) {
    db.prepare("UPDATE devices SET updated_at = datetime('now') WHERE id = ?").run(existing.id);
    res.json({ deviceId: existing.id });
    return;
  }

  const result = db.prepare('INSERT INTO devices (device_token) VALUES (?)').run(deviceToken);
  res.status(201).json({ deviceId: result.lastInsertRowid });
});

export default router;
