import { Router, Request, Response } from 'express';
import { config, updateTrackerCredentials } from '../config.js';
import { getCredentialHealth, resetCredentialExpired } from '../services/credentialMonitor.js';
import { resetClient } from '../services/trackerApi.js';
import { forcePush } from '../services/pushService.js';
import { getDb } from '../db/database.js';
import {
  listHubs, countUnmappedHubs, saveManualHub, retryHub, isKakaoConfigured,
  type HubRow,
} from '../services/hubGeocoder.js';

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

// GET /admin/force-push?secret=<admin>&number=<운송장번호>  (또는 &tracking=<id>)
// [디버그] 현재 상태로 즉시 푸시를 쏘고 APNs 결과 코드 + 원인 힌트를 JSON 으로 반환.
router.get('/force-push', requireAuth, async (req: Request, res: Response) => {
  let id = Number(req.query.tracking);
  if (!Number.isFinite(id) && req.query.number) {
    const row = getDb()
      .prepare('SELECT id FROM trackings WHERE tracking_number = ? ORDER BY id DESC LIMIT 1')
      .get(String(req.query.number)) as { id: number } | undefined;
    if (row) id = row.id;
  }
  if (!Number.isFinite(id)) {
    res.status(400).json({ error: 'tracking(숫자 id) 또는 number(운송장번호) 쿼리가 필요합니다.' });
    return;
  }
  res.json(await forcePush(id));
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

// GET /admin/hubs — 허브 좌표 관리 페이지
router.get('/hubs', requireAuth, (req: Request, res: Response) => {
  res.send(renderHubPage(listHubs(), countUnmappedHubs(), String(req.query.secret ?? '')));
});

// POST /admin/hubs — 좌표 직접 입력(검색이 못 찾은 허브를 살린다)
router.post('/hubs', requireAuth, (req: Request, res: Response) => {
  const { name } = req.body;
  const lat = Number(req.body.lat);
  const lon = Number(req.body.lon);

  if (!name || !Number.isFinite(lat) || !Number.isFinite(lon)) {
    res.status(400).json({ error: 'name, lat, lon 이 모두 필요합니다.' });
    return;
  }
  if (Math.abs(lat) > 90 || Math.abs(lon) > 180) {
    res.status(400).json({ error: '좌표 범위를 벗어났습니다. (위도 ±90, 경도 ±180)' });
    return;
  }

  saveManualHub(String(name), lat, lon);
  res.json({ success: true });
});

// POST /admin/hubs/retry — 실패 표시를 지워 다음 주기에 다시 검색되게 한다
router.post('/hubs/retry', requireAuth, (req: Request, res: Response) => {
  if (!req.body?.name) {
    res.status(400).json({ error: 'name 이 필요합니다.' });
    return;
  }
  retryHub(String(req.body.name));
  res.json({ success: true });
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

    <p style="text-align:center;margin-top:16px">
      <a id="hubsLink" href="/admin/hubs" style="color:#4A7DFF;font-size:13px;text-decoration:none">허브 좌표 관리 →</a>
    </p>
  </div>

  <script>
    const secret = new URLSearchParams(window.location.search).get('secret') || '';
    document.getElementById('hubsLink').href = '/admin/hubs?secret=' + encodeURIComponent(secret);

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

/**
 * 허브 좌표 관리 페이지.
 * 지도에 찍으려면 위치 이름마다 좌표가 필요한데, 검색으로 못 찾는 이름이 남는다.
 * 실패한 것을 위로 올려 여기서 직접 채운다.
 */
function renderHubPage(hubs: HubRow[], pending: number, secret: string): string {
  const failed = hubs.filter(h => h.status !== 'ok');
  const ok = hubs.filter(h => h.status === 'ok');

  const row = (h: HubRow) => `
    <tr data-name="${escapeHtml(h.name)}">
      <td class="name">${escapeHtml(h.name)}<span class="uses">${h.uses}회</span></td>
      <td><input class="lat" type="text" inputmode="decimal" value="${h.lat ?? ''}" placeholder="위도"></td>
      <td><input class="lon" type="text" inputmode="decimal" value="${h.lon ?? ''}" placeholder="경도"></td>
      <td class="src">${h.source === 'manual' ? '직접' : '검색'}</td>
      <td class="actions">
        <button class="save">저장</button>
        <button class="retry" title="검색을 다시 시도">재검색</button>
      </td>
    </tr>`;

  return `<!DOCTYPE html>
<html lang="ko">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Waito 허브 좌표</title>
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
           background: #0A0A0A; color: #E0E0E0; padding: 24px; }
    .container { max-width: 760px; margin: 0 auto; }
    h1 { font-size: 22px; color: #FFF; }
    .sub { font-size: 13px; color: #888; margin: 6px 0 20px; }
    .card { background: #1A1A1A; border: 1px solid #2A2A2A; border-radius: 16px;
            padding: 20px; margin-bottom: 16px; }
    .card h2 { font-size: 15px; margin-bottom: 4px; color: #FFF; }
    .card .hint { font-size: 12px; color: #888; margin-bottom: 14px; }
    table { width: 100%; border-collapse: collapse; }
    td { padding: 7px 6px; border-bottom: 1px solid #222; vertical-align: middle; font-size: 13px; }
    td.name { min-width: 150px; }
    .uses { color: #666; font-size: 11px; margin-left: 6px; }
    .src { color: #777; font-size: 12px; width: 44px; }
    input { width: 104px; background: #101010; border: 1px solid #2E2E2E; border-radius: 8px;
            color: #E0E0E0; padding: 7px 8px; font-size: 13px; }
    input:focus { outline: none; border-color: #4A7DFF; }
    .actions { text-align: right; white-space: nowrap; }
    button { background: #4A7DFF; border: 0; border-radius: 8px; color: #FFF;
             padding: 7px 12px; font-size: 12px; cursor: pointer; }
    button.retry { background: #2A2A2A; margin-left: 6px; }
    button:disabled { opacity: .5; cursor: default; }
    .empty { color: #666; font-size: 13px; }
    .warn { background: #2A1A00; border: 1px solid #553300; border-radius: 8px;
            padding: 12px; font-size: 13px; color: #FFAA00; margin-bottom: 16px; }
    .back { display: inline-block; margin-top: 8px; color: #4A7DFF; font-size: 13px; text-decoration: none; }
  </style>
</head>
<body>
  <div class="container">
    <h1>허브 좌표</h1>
    <p class="sub">위치 이름을 지도 좌표로 이어 둔 표. 대기 ${pending}곳 · 실패 ${failed.length}곳 · 완료 ${ok.length}곳</p>

    ${isKakaoConfigured() ? '' : '<div class="warn">카카오 검색 키가 없어 자동 변환이 멈춰 있음. 서버 환경변수에 키를 넣으면 10분 주기로 채워짐.</div>'}

    <div class="card">
      <h2>좌표를 못 찾은 곳</h2>
      <p class="hint">지도에서 빠지는 지점. 좌표를 직접 넣으면 살아남. 지도에서 위치를 우클릭하면 좌표를 얻을 수 있음.</p>
      ${failed.length ? `<table>${failed.map(row).join('')}</table>` : '<p class="empty">없음</p>'}
    </div>

    <div class="card">
      <h2>좌표가 있는 곳</h2>
      <p class="hint">값이 이상하면 여기서 고칠 수 있음.</p>
      ${ok.length ? `<table>${ok.map(row).join('')}</table>` : '<p class="empty">아직 없음</p>'}
    </div>

    <a class="back" href="/admin?secret=${encodeURIComponent(secret)}">← 관리자 홈</a>
  </div>

  <script>
    const secret = ${JSON.stringify(secret)};

    async function post(path, body, button, doneLabel) {
      const original = button.textContent;
      button.disabled = true;
      button.textContent = '...';
      try {
        const res = await fetch(path + '?secret=' + encodeURIComponent(secret), {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(body),
        });
        const data = await res.json();
        if (!res.ok) throw new Error(data.error || '실패');
        button.textContent = doneLabel;
        setTimeout(() => location.reload(), 500);
      } catch (e) {
        alert(e.message);
        button.disabled = false;
        button.textContent = original;
      }
    }

    document.addEventListener('click', (event) => {
      const button = event.target;
      const tr = button.closest('tr');
      if (!tr) return;
      const name = tr.dataset.name;

      if (button.classList.contains('save')) {
        post('/admin/hubs', {
          name,
          lat: tr.querySelector('.lat').value.trim(),
          lon: tr.querySelector('.lon').value.trim(),
        }, button, '저장됨');
      } else if (button.classList.contains('retry')) {
        post('/admin/hubs/retry', { name }, button, '대기');
      }
    });
  </script>
</body>
</html>`;
}

function escapeHtml(value: string): string {
  return value
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

export default router;
