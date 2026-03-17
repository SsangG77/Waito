import { Router, Request, Response } from 'express';
import { config, updateTrackerCredentials } from '../config.js';
import { getCredentialHealth, resetCredentialExpired } from '../services/credentialMonitor.js';
import { resetClient } from '../services/trackerApi.js';

const router = Router();

// 간단한 admin secret 검증 미들웨어
function requireAuth(req: Request, res: Response, next: () => void) {
  const secret = req.query.secret || req.headers['x-admin-secret'];
  if (secret !== config.admin.secret) {
    res.status(401).send('Unauthorized');
    return;
  }
  next();
}

// GET /admin — 어드민 페이지
router.get('/', requireAuth, (_req: Request, res: Response) => {
  const health = getCredentialHealth();
  res.send(renderAdminPage(health));
});

// GET /admin/credential — credential 상태 JSON
router.get('/credential', requireAuth, (_req: Request, res: Response) => {
  res.json(getCredentialHealth());
});

// POST /admin/credential — credential 갱신
router.post('/credential', requireAuth, (req: Request, res: Response) => {
  const { clientId, clientSecret } = req.body;

  if (!clientId || !clientSecret) {
    res.status(400).json({ error: 'clientId와 clientSecret 모두 필요합니다.' });
    return;
  }

  // 1. config + .env 업데이트
  updateTrackerCredentials(clientId, clientSecret);

  // 2. GraphQL 클라이언트 재생성
  resetClient();

  // 3. 만료 플래그 초기화
  resetCredentialExpired();

  console.log('[Admin] Credential 갱신 완료');

  res.json({
    success: true,
    credential: getCredentialHealth(),
  });
});

function renderAdminPage(health: ReturnType<typeof getCredentialHealth>): string {
  const statusColor = !health.isValid ? '#FF4444'
    : (health.daysRemaining !== null && health.daysRemaining <= 3) ? '#FFAA00'
    : '#44DD66';

  const statusEmoji = !health.isValid ? '🔴'
    : (health.daysRemaining !== null && health.daysRemaining <= 3) ? '🟡'
    : '🟢';

  const progressPercent = health.daysRemaining !== null
    ? Math.max(0, Math.min(100, (health.daysRemaining / 21) * 100))
    : 0;

  return `<!DOCTYPE html>
<html lang="ko">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Waito Admin</title>
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
      background: #0A0A0A;
      color: #E0E0E0;
      min-height: 100vh;
      display: flex;
      align-items: center;
      justify-content: center;
    }
    .container {
      width: 100%;
      max-width: 480px;
      padding: 24px;
    }
    .header {
      text-align: center;
      margin-bottom: 32px;
    }
    .header h1 {
      font-size: 24px;
      font-weight: 700;
      color: #FFF;
    }
    .header p {
      font-size: 13px;
      color: #888;
      margin-top: 4px;
    }

    /* Status Card */
    .card {
      background: #1A1A1A;
      border: 1px solid #2A2A2A;
      border-radius: 16px;
      padding: 24px;
      margin-bottom: 16px;
    }
    .status-row {
      display: flex;
      align-items: center;
      justify-content: space-between;
      margin-bottom: 16px;
    }
    .status-label {
      font-size: 14px;
      color: #888;
    }
    .status-value {
      font-size: 14px;
      font-weight: 600;
      color: ${statusColor};
    }
    .progress-bar {
      width: 100%;
      height: 8px;
      background: #2A2A2A;
      border-radius: 4px;
      overflow: hidden;
      margin-bottom: 12px;
    }
    .progress-fill {
      height: 100%;
      width: ${progressPercent}%;
      background: ${statusColor};
      border-radius: 4px;
      transition: width 0.5s ease;
    }
    .warning {
      background: #2A1A00;
      border: 1px solid #553300;
      border-radius: 8px;
      padding: 12px;
      font-size: 13px;
      color: #FFAA00;
      margin-top: 12px;
      display: ${health.warning ? 'block' : 'none'};
    }

    /* Renew Card */
    .renew-card {
      background: #1A1A1A;
      border: 1px solid #2A2A2A;
      border-radius: 16px;
      padding: 24px;
    }
    .renew-card h2 {
      font-size: 16px;
      font-weight: 600;
      color: #FFF;
      margin-bottom: 4px;
    }
    .renew-card .desc {
      font-size: 13px;
      color: #888;
      margin-bottom: 20px;
    }
    .step {
      display: flex;
      gap: 12px;
      margin-bottom: 20px;
    }
    .step-num {
      width: 24px;
      height: 24px;
      background: #2A2A2A;
      border-radius: 50%;
      display: flex;
      align-items: center;
      justify-content: center;
      font-size: 12px;
      font-weight: 700;
      color: #888;
      flex-shrink: 0;
      margin-top: 2px;
    }
    .step-content {
      font-size: 14px;
      color: #CCC;
      line-height: 1.5;
    }
    .step-content a {
      color: #6EA8FE;
      text-decoration: none;
    }
    .step-content a:hover {
      text-decoration: underline;
    }

    .input-group {
      margin-bottom: 12px;
    }
    .input-group label {
      display: block;
      font-size: 12px;
      color: #888;
      margin-bottom: 6px;
      font-weight: 500;
    }
    .input-group input {
      width: 100%;
      padding: 10px 14px;
      background: #0A0A0A;
      border: 1px solid #333;
      border-radius: 8px;
      color: #FFF;
      font-size: 14px;
      font-family: 'SF Mono', 'Fira Code', monospace;
      outline: none;
      transition: border-color 0.2s;
    }
    .input-group input:focus {
      border-color: #6EA8FE;
    }
    .input-group input::placeholder {
      color: #555;
    }

    .btn {
      width: 100%;
      padding: 12px;
      border: none;
      border-radius: 10px;
      font-size: 15px;
      font-weight: 600;
      cursor: pointer;
      transition: all 0.2s;
      margin-top: 8px;
    }
    .btn-primary {
      background: #FFF;
      color: #000;
    }
    .btn-primary:hover {
      background: #E0E0E0;
    }
    .btn-primary:disabled {
      background: #333;
      color: #666;
      cursor: not-allowed;
    }

    .result {
      margin-top: 16px;
      padding: 12px;
      border-radius: 8px;
      font-size: 13px;
      display: none;
    }
    .result.success {
      background: #0A2A0A;
      border: 1px solid #1A5A1A;
      color: #44DD66;
      display: block;
    }
    .result.error {
      background: #2A0A0A;
      border: 1px solid #5A1A1A;
      color: #FF4444;
      display: block;
    }

    .divider {
      border: none;
      border-top: 1px solid #2A2A2A;
      margin: 20px 0;
    }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <h1>Waito Admin</h1>
      <p>tracker.delivery Credential 관리</p>
    </div>

    <!-- Status Card -->
    <div class="card" id="statusCard">
      <div class="status-row">
        <span class="status-label">상태</span>
        <span class="status-value" id="statusText">${statusEmoji} ${health.isValid ? '정상' : '만료됨'}</span>
      </div>
      <div class="progress-bar">
        <div class="progress-fill" id="progressFill"></div>
      </div>
      <div class="status-row">
        <span class="status-label">발급일</span>
        <span style="font-size:14px;color:#CCC" id="issuedAt">${health.issuedAt || '-'}</span>
      </div>
      <div class="status-row">
        <span class="status-label">만료일</span>
        <span style="font-size:14px;color:#CCC" id="expiresAt">${health.expiresAt || '-'}</span>
      </div>
      <div class="status-row" style="margin-bottom:0">
        <span class="status-label">남은 기간</span>
        <span style="font-size:14px;font-weight:600;color:${statusColor}" id="daysRemaining">
          ${health.daysRemaining !== null ? health.daysRemaining + '일' : '-'}
        </span>
      </div>
      <div class="warning" id="warningBox">${health.warning || ''}</div>
    </div>

    <!-- Renew Card -->
    <div class="renew-card">
      <h2>Credential 갱신</h2>
      <p class="desc">tracker.delivery 무료 티어는 21일마다 수동 갱신이 필요합니다.</p>

      <div class="step">
        <div class="step-num">1</div>
        <div class="step-content">
          <a href="https://tracker.delivery/console" target="_blank" rel="noopener">
            tracker.delivery 콘솔 열기 ↗
          </a><br>
          로그인 후 새 Client ID / Secret을 발급받으세요.
        </div>
      </div>

      <div class="step">
        <div class="step-num">2</div>
        <div class="step-content">
          발급받은 credential을 아래에 입력하세요.
        </div>
      </div>

      <hr class="divider">

      <form id="renewForm">
        <div class="input-group">
          <label>Client ID</label>
          <input type="text" id="clientId" placeholder="ck_xxxxxxxxxxxxxxxx" autocomplete="off" required>
        </div>
        <div class="input-group">
          <label>Client Secret</label>
          <input type="password" id="clientSecret" placeholder="cs_xxxxxxxxxxxxxxxx" autocomplete="off" required>
        </div>
        <button type="submit" class="btn btn-primary" id="submitBtn">Credential 갱신</button>
      </form>

      <div class="result" id="result"></div>
    </div>
  </div>

  <script>
    const secret = new URLSearchParams(window.location.search).get('secret') || '';

    document.getElementById('renewForm').addEventListener('submit', async (e) => {
      e.preventDefault();

      const btn = document.getElementById('submitBtn');
      const result = document.getElementById('result');
      const clientId = document.getElementById('clientId').value.trim();
      const clientSecret = document.getElementById('clientSecret').value.trim();

      if (!clientId || !clientSecret) return;

      btn.disabled = true;
      btn.textContent = '갱신 중...';
      result.className = 'result';
      result.style.display = 'none';

      try {
        const res = await fetch('/admin/credential?secret=' + encodeURIComponent(secret), {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ clientId, clientSecret }),
        });

        const data = await res.json();

        if (res.ok && data.success) {
          result.className = 'result success';
          result.textContent = '갱신 완료! 다음 만료일: ' + (data.credential.expiresAt || '-');
          result.style.display = 'block';

          // 상태 카드 업데이트
          updateStatusCard(data.credential);

          document.getElementById('clientId').value = '';
          document.getElementById('clientSecret').value = '';
        } else {
          result.className = 'result error';
          result.textContent = data.error || '갱신에 실패했습니다.';
          result.style.display = 'block';
        }
      } catch (err) {
        result.className = 'result error';
        result.textContent = '서버 연결에 실패했습니다.';
        result.style.display = 'block';
      }

      btn.disabled = false;
      btn.textContent = 'Credential 갱신';
    });

    function updateStatusCard(cred) {
      const color = !cred.isValid ? '#FF4444'
        : (cred.daysRemaining !== null && cred.daysRemaining <= 3) ? '#FFAA00'
        : '#44DD66';
      const emoji = !cred.isValid ? '\\u{1F534}' : (cred.daysRemaining <= 3) ? '\\u{1F7E1}' : '\\u{1F7E2}';
      const pct = cred.daysRemaining !== null ? Math.max(0, Math.min(100, (cred.daysRemaining / 21) * 100)) : 0;

      document.getElementById('statusText').textContent = emoji + ' ' + (cred.isValid ? '정상' : '만료됨');
      document.getElementById('statusText').style.color = color;
      document.getElementById('progressFill').style.width = pct + '%';
      document.getElementById('progressFill').style.background = color;
      document.getElementById('issuedAt').textContent = cred.issuedAt || '-';
      document.getElementById('expiresAt').textContent = cred.expiresAt || '-';
      document.getElementById('daysRemaining').textContent = cred.daysRemaining !== null ? cred.daysRemaining + '일' : '-';
      document.getElementById('daysRemaining').style.color = color;

      const warn = document.getElementById('warningBox');
      if (cred.warning) {
        warn.textContent = cred.warning;
        warn.style.display = 'block';
      } else {
        warn.style.display = 'none';
      }
    }
  </script>
</body>
</html>`;
}

export default router;
