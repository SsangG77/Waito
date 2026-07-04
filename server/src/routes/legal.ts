import { Router, Request, Response } from 'express';

// 앱스토어 심사(Guideline 3.1.2(c)) 필수: 구독 결제 화면에서 열리는
// 개인정보처리방침 / 이용약관(EULA) 페이지를 서버가 정적 HTML 로 제공한다.
// 앱은 http://<서버>/privacy, /terms 로 링크한다. ASC 메타데이터에도 같은 URL 사용.

const router = Router();

const EFFECTIVE_DATE = '2026-07-04';
const CONTACT_EMAIL = 'sangjincha719@gmail.com';
const APPLE_STD_EULA = 'https://www.apple.com/legal/internet-services/itunes/dev/stdeula/';

/** 공통 레이아웃 (읽기 쉬운 라이트 테마, 의존성 0) */
function page(title: string, body: string): string {
  return `<!DOCTYPE html>
<html lang="ko">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1" />
<meta name="robots" content="noindex" />
<title>${title} · Waito</title>
<style>
  :root { color-scheme: light; }
  body { font-family: -apple-system, BlinkMacSystemFont, "Apple SD Gothic Neo", sans-serif;
         max-width: 720px; margin: 0 auto; padding: 28px 20px 64px; line-height: 1.7; color: #1c1c1e; }
  h1 { font-size: 22px; margin: 8px 0 4px; }
  h2 { font-size: 16px; margin: 28px 0 8px; }
  p, li { font-size: 14px; }
  ul { padding-left: 20px; }
  .meta { color: #6b7280; font-size: 12px; margin-bottom: 20px; }
  a { color: #2563eb; }
  hr { border: none; border-top: 1px solid #e5e7eb; margin: 28px 0; }
  code { background: #f3f4f6; padding: 1px 5px; border-radius: 4px; font-size: 13px; }
</style>
</head>
<body>
${body}
<hr />
<p class="meta">문의: <a href="mailto:${CONTACT_EMAIL}">${CONTACT_EMAIL}</a> · 시행일 ${EFFECTIVE_DATE}</p>
</body>
</html>`;
}

// GET /privacy — 개인정보처리방침
router.get('/privacy', (_req: Request, res: Response) => {
  const body = `
<h1>개인정보처리방침</h1>
<p class="meta">Waito (택배 배송 추적 앱)</p>

<p>Waito(이하 "앱")는 이용자의 개인정보를 소중히 다루며, 배송 추적 기능 제공에 필요한 최소한의 정보만 처리합니다. 별도의 회원가입·로그인이 없으며 이름·이메일·전화번호 등 개인 식별정보를 수집하지 않습니다.</p>

<h2>1. 수집·처리하는 정보</h2>
<ul>
  <li><b>이용자가 입력한 배송 정보</b>: 운송장 번호, 택배사, 상품명, 메모 — 배송 상태 조회·표시를 위해 사용합니다.</li>
  <li><b>기기 식별 토큰</b>: 앱이 기기에서 생성해 저장하는 임의 식별자 — 여러 기기를 구분하고 알림을 보내기 위해 사용합니다. (특정 개인을 식별하지 않습니다.)</li>
  <li><b>푸시 알림 토큰(APNs)</b>: 배송 상태 변경 알림 및 실시간 활동(Live Activity) 갱신을 위해 사용합니다.</li>
  <li><b>배송 이벤트 데이터</b>: 택배사 조회 결과(배송 단계·시간·위치 등) — 화면에 표시하기 위해 저장합니다.</li>
  <li><b>앱 내 보상 데이터</b>: 배송 완료 횟수·해제한 트럭 부품 등(기기 단위).</li>
</ul>
<p>위치 정보, 연락처, 사진 등 기기의 민감 정보는 수집하지 않습니다.</p>

<h2>2. 제3자 제공 및 처리 위탁</h2>
<ul>
  <li><b>Delivery Tracker (tracker.delivery)</b>: 배송 상태 조회를 위해 운송장 번호·택배사 정보를 전송합니다.</li>
  <li><b>Apple Push Notification service (APNs)</b>: 알림 전송을 위해 푸시 토큰을 사용합니다.</li>
</ul>

<h2>3. 보관 및 파기</h2>
<p>배송 정보는 이용자가 앱에서 해당 택배를 삭제하면 서버에서도 삭제됩니다. 기기 식별·푸시 토큰은 알림 제공 목적이 사라지면(앱 삭제·토큰 무효화 등) 파기됩니다.</p>

<h2>4. 이용자의 권리</h2>
<p>이용자는 앱에서 언제든 등록한 택배를 삭제할 수 있으며, 기기 설정에서 알림 권한을 해제할 수 있습니다. 그 밖의 문의는 아래 이메일로 요청할 수 있습니다.</p>

<h2>5. 결제 정보</h2>
<p>구독 결제는 Apple의 App Store를 통해 처리되며, 앱은 이용자의 결제 수단·카드 정보를 수집하거나 저장하지 않습니다.</p>

<h2>6. 변경 고지</h2>
<p>본 방침은 관련 법령·서비스 변경에 따라 개정될 수 있으며, 개정 시 본 페이지를 통해 고지합니다.</p>
`;
  res.type('html').send(page('개인정보처리방침', body));
});

// GET /terms — 이용약관(EULA) + 구독 안내
router.get('/terms', (_req: Request, res: Response) => {
  const body = `
<h1>이용약관 (End User License Agreement)</h1>
<p class="meta">Waito (택배 배송 추적 앱)</p>

<p>본 약관은 Waito 앱 및 유료 구독 "Waito Plus"의 이용 조건을 규정합니다. 앱을 사용함으로써 본 약관과 Apple의 표준 최종 사용자 사용권 계약에 동의하는 것으로 간주합니다.</p>

<h2>1. 서비스</h2>
<p>Waito는 이용자가 입력한 운송장 번호로 택배 배송 상태를 조회하고, Dynamic Island·잠금화면·알림으로 시각적으로 보여주는 앱입니다.</p>

<h2>2. 구독 (Waito Plus)</h2>
<ul>
  <li><b>구독 상품명</b>: Waito Plus</li>
  <li><b>구독 기간</b>: 1개월 (자동 갱신)</li>
  <li><b>가격</b>: ₩3,300 / 월 (₩3,300 per month)</li>
  <li><b>혜택</b>: Live Activity 동시 2개 추적, 프리미엄 트럭 스킨/부품 잠금 해제, "항상 노출" 기능.</li>
</ul>
<p>구독은 <b>자동 갱신</b>됩니다. 현재 구독 기간이 끝나기 최소 24시간 전에 해지하지 않으면 동일 금액으로 자동 갱신되며, 요금은 Apple 계정으로 청구됩니다. 구입 확정 시점에 결제됩니다.</p>

<h2>3. 해지 및 환불</h2>
<p>구독 해지는 기기의 <code>설정 &gt; Apple 계정 &gt; 구독</code>에서 언제든 할 수 있으며, 현재 결제 기간이 끝나면 갱신이 중단됩니다. 환불은 Apple의 정책에 따릅니다.</p>

<h2>4. 표준 EULA</h2>
<p>본 앱에는 Apple의 표준 최종 사용자 사용권 계약(Standard EULA)이 함께 적용됩니다: <a href="${APPLE_STD_EULA}">Apple Standard EULA</a></p>

<h2>5. 면책</h2>
<p>배송 상태 정보는 택배사·조회 서비스가 제공하는 데이터에 기반하며, 실제 배송과 차이가 있을 수 있습니다. 앱은 배송 지연·오류에 대해 책임지지 않습니다.</p>
`;
  res.type('html').send(page('이용약관', body));
});

export default router;
