import { config } from '../config.js';

/**
 * Resend HTTP API로 알림 이메일을 보낸다.
 * 외부 npm 패키지 없이 Node 20 내장 fetch만 사용한다(apnsClient와 동일 철학).
 * RESEND_API_KEY 또는 ALERT_EMAIL_TO가 없으면 graceful skip.
 */
export async function sendAlertEmail(subject: string, html: string): Promise<boolean> {
  const { resendApiKey, emailTo, emailFrom } = config.alert;

  if (!resendApiKey || !emailTo) {
    console.warn('[Email] RESEND_API_KEY 또는 ALERT_EMAIL_TO 미설정 → 이메일 전송 건너뜀');
    return false;
  }

  try {
    const res = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${resendApiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        from: emailFrom,
        to: [emailTo],
        subject,
        html,
      }),
    });

    if (!res.ok) {
      const body = await res.text();
      console.error(`[Email] 전송 실패 (HTTP ${res.status}): ${body}`);
      return false;
    }

    console.log(`[Email] 알림 전송 완료 → ${emailTo}`);
    return true;
  } catch (err) {
    console.error('[Email] 전송 중 오류:', err);
    return false;
  }
}
