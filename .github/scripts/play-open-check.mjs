// فحص الاختبار المفتوح (بدون أي تغيير): ننسخ آخر نسخة من الاختبار المغلق لمسار الاختبار المفتوح داخل تعديل مؤقت،
// ونطلب من Google التحقق منه، وبعدها نحذف التعديل (ما ينحفظ شي)
import { createSign } from 'node:crypto';
import { fixKey } from './play-key.mjs';
const sa = fixKey(process.env.SA || '{}');
const b64u = (x) => Buffer.from(x).toString('base64url');
const now = Math.floor(Date.now() / 1000);
const unsigned = `${b64u(JSON.stringify({ alg: 'RS256', typ: 'JWT' }))}.${b64u(JSON.stringify({ iss: sa.client_email, scope: 'https://www.googleapis.com/auth/androidpublisher', aud: sa.token_uri, iat: now, exp: now + 600 }))}`;
const sig = createSign('RSA-SHA256').update(unsigned).sign(sa.private_key, 'base64url');
const tok = await (await fetch(sa.token_uri, { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${unsigned}.${sig}` })).json();
const base = 'https://androidpublisher.googleapis.com/androidpublisher/v3/applications/com.majlisk.app';
const api = async (path, method = 'GET', body) => {
  const r = await fetch(`${base}${path}`, { method, headers: { Authorization: `Bearer ${tok.access_token}`, 'Content-Type': 'application/json' }, body: body ? JSON.stringify(body) : undefined });
  const t = await r.text();
  if (!r.ok) throw new Error(`${method} ${path} → ${r.status}: ${t.slice(0, 600)}`);
  return t ? JSON.parse(t) : {};
};
const edit = await api('/edits', 'POST');
try {
  const alpha = await api(`/edits/${edit.id}/tracks/alpha`);
  const codes = (alpha.releases ?? []).flatMap((r) => r.versionCodes ?? []).map(Number).sort((a, b) => b - a);
  console.log(`آخر نسخة في الاختبار المغلق: ${codes[0] ?? 'لا يوجد'}`);
  if (!codes[0]) throw new Error('ما فيه نسخة في الاختبار المغلق');
  await api(`/edits/${edit.id}/tracks/beta`, 'PUT', { track: 'beta', releases: [{ versionCodes: [String(codes[0])], status: 'completed' }] });
  console.log('✓ تحديث مسار الاختبار المفتوح داخل التعديل المؤقت');
  await api(`/edits/${edit.id}:validate`, 'POST');
  console.log('### ✅ الاختبار المفتوح متاح: Google قبلت النسخة فيه (ما انحفظ شي)');
} catch (e) {
  console.log(`### ❌ ${e.message}`);
} finally {
  await api(`/edits/${edit.id}`, 'DELETE').catch(() => {});
}
