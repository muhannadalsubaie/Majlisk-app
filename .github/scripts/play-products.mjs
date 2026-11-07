// ينشئ (أو يحدّث) باقات العملات في Google Play: مُدارة (تُستهلك بعد الشراء)، فعّالة، بالريال، وباقي الدول تتحول تلقائياً
import { createSign } from 'node:crypto';
import { fixKey } from './play-key.mjs';
const PACKS = [
  { sku: 'coins_20', sar: 3.99, title: '20 عملة', desc: '20 عملة للعب في مجلسك' },
  { sku: 'coins_70', sar: 9.99, title: '80 عملة', desc: '70 عملة + 10 هدية للعب في مجلسك' },
  { sku: 'coins_190', sar: 19.99, title: '230 عملة', desc: '190 عملة + 40 هدية للعب في مجلسك' },
  { sku: 'coins_550', sar: 44.99, title: '700 عملة', desc: '550 عملة + 150 هدية للعب في مجلسك' },
];
let sa = {};
try { sa = fixKey(process.env.SA || '{}'); } catch (e) { console.log(`### ❌ ملف المفتاح غير صالح: ${e.message}`); process.exit(1); }
const b64u = (x) => Buffer.from(x).toString('base64url');
const now = Math.floor(Date.now() / 1000);
const unsigned = `${b64u(JSON.stringify({ alg: 'RS256', typ: 'JWT' }))}.${b64u(JSON.stringify({ iss: sa.client_email, scope: 'https://www.googleapis.com/auth/androidpublisher', aud: sa.token_uri, iat: now, exp: now + 600 }))}`;
const sig = createSign('RSA-SHA256').update(unsigned).sign(sa.private_key, 'base64url');
const tok = await (await fetch(sa.token_uri, { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${unsigned}.${sig}` })).json();
if (!tok.access_token) { console.log('### ❌ فشل الدخول بالمفتاح'); process.exit(1); }
const PKG = 'com.majlisk.app';
const base = `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${PKG}`;
const api = async (path, method = 'GET', body) => {
  const r = await fetch(`${base}${path}`, { method, headers: { Authorization: `Bearer ${tok.access_token}`, 'Content-Type': 'application/json' }, body: body ? JSON.stringify(body) : undefined });
  const t = await r.text();
  return { ok: r.ok, status: r.status, body: t ? (() => { try { return JSON.parse(t); } catch { return t; } })() : {} };
};
// لغة المتجر الافتراضية للتطبيق
const edit = await api('/edits', 'POST');
const details = edit.ok ? await api(`/edits/${edit.body.id}/details`) : { body: {} };
if (edit.ok) await api(`/edits/${edit.body.id}`, 'DELETE');
const lang = details.body?.defaultLanguage || 'ar';
console.log(`default language: ${lang}`);
let failed = false;
for (const p of PACKS) {
  const product = {
    packageName: PKG, sku: p.sku, status: 'active', purchaseType: 'managedUser', defaultLanguage: lang,
    defaultPrice: { priceMicros: String(Math.round(p.sar * 1_000_000)), currency: 'SAR' },
    listings: { [lang]: { title: p.title, description: p.desc } },
  };
  const exists = (await api(`/inappproducts/${p.sku}`)).ok;
  const r = exists
    ? await api(`/inappproducts/${p.sku}?autoConvertMissingPrices=true&allowMissing=true`, 'PUT', product)
    : await api(`/inappproducts?autoConvertMissingPrices=true`, 'POST', product);
  if (r.ok) console.log(`- ✅ ${p.sku}: ${exists ? 'تحدّث' : 'انضاف'} (${p.sar} ر.س)`);
  else { failed = true; console.log(`- ❌ ${p.sku}: ${r.status} ${JSON.stringify(r.body).slice(0, 500)}`); }
}
if (failed) process.exit(1);
console.log('### ✅ باقات العملات جاهزة في Google Play');
