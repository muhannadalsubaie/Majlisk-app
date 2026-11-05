// فحص مفتاح Google Play (قراءة فقط): يدخل بالمفتاح ويقرأ المسارات والنسخ، ثم يحذف التعديل بدون أي تغيير
import { createSign } from 'node:crypto';
import { fixKey } from './play-key.mjs';
let sa = {};
try { sa = fixKey(process.env.SA || '{}'); } catch (e) { console.log(`### ❌ ملف المفتاح غير صالح: ${e.message}`); process.exit(1); }
if (!sa.client_email) { console.log('### ❌ السر PLAY_SERVICE_ACCOUNT_JSON غير موجود أو غير صالح'); process.exit(1); }
console.log(`service account: ${sa.client_email}`);
const b64u = (x) => Buffer.from(x).toString('base64url');
const now = Math.floor(Date.now() / 1000);
const unsigned = `${b64u(JSON.stringify({ alg: 'RS256', typ: 'JWT' }))}.${b64u(JSON.stringify({ iss: sa.client_email, scope: 'https://www.googleapis.com/auth/androidpublisher', aud: sa.token_uri, iat: now, exp: now + 600 }))}`;
const sig = createSign('RSA-SHA256').update(unsigned).sign(sa.private_key, 'base64url');
const tok = await (await fetch(sa.token_uri, { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${unsigned}.${sig}` })).json();
if (!tok.access_token) { console.log('### ❌ فشل الدخول بالمفتاح', JSON.stringify(tok)); process.exit(1); }
const base = 'https://androidpublisher.googleapis.com/androidpublisher/v3/applications/com.majlisk.app';
const api = async (path, method = 'GET') => {
  const r = await fetch(`${base}${path}`, { method, headers: { Authorization: `Bearer ${tok.access_token}` } });
  const t = await r.text();
  if (!r.ok) throw new Error(`${method} ${path} → ${r.status}: ${t.slice(0, 400)}`);
  return t ? JSON.parse(t) : {};
};
try {
  const edit = await api('/edits', 'POST');
  const tracks = await api(`/edits/${edit.id}/tracks`);
  for (const t of tracks.tracks ?? []) console.log(`${t.track}: ${(t.releases ?? []).map((r) => `${r.status} [${(r.versionCodes ?? []).join(',')}]`).join(' | ') || '—'}`);
  await api(`/edits/${edit.id}`, 'DELETE');
  console.log('### ✅ مفتاح Google Play يشتغل');
} catch (e) { console.log(`### ❌ ${e.message}`); process.exit(1); }
