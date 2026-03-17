import { Router, Request, Response } from 'express';
import { CARRIERS } from '../types/delivery.js';

const router = Router();

// GET /api/carriers
router.get('/', (_req: Request, res: Response) => {
  res.json(CARRIERS.map(c => ({ id: c.id, name: c.name })));
});

export default router;
