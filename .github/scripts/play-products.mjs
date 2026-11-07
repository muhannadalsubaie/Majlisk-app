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
// الواجهة الجديدة (monetization.onetimeproducts): خيار شراء «buy» متوافق مع مكتبة الدفع، بسعر بالريال محوّل لكل الدول
const LT = 'PRODUCT_UPDATE_LATENCY_TOLERANCE_LATENCY_TOLERANT';
const money = (cur, v) => ({ currencyCode: cur, units: String(Math.floor(v)), nanos: Math.round((v - Math.floor(v)) * 1e9) });
let failed = false;
for (const p of PACKS) {
  const conv = await api('/pricing:convertRegionPrices', 'POST', { price: money('SAR', p.sar) });
  if (!conv.ok) console.log(`  (تحويل الأسعار: ${conv.status} ${JSON.stringify(conv.body).slice(0, 300)})`);
  const version = conv.body?.regionVersion?.version || '2022/02';
  const regions = Object.values(conv.body?.convertedRegionPrices ?? {}).map((r) => ({ regionCode: r.regionCode, price: r.price, availability: 'AVAILABLE' }));
  if (!regions.some((r) => r.regionCode === 'SA')) regions.push({ regionCode: 'SA', price: money('SAR', p.sar), availability: 'AVAILABLE' });
  const other = conv.body?.convertedOtherRegionsPrice;
  const product = (regs) => ({
    packageName: PKG, productId: p.sku,
    listings: [{ languageCode: lang, title: p.title, description: p.desc }],
    purchaseOptions: [{
      purchaseOptionId: 'buy',
      buyOption: { legacyCompatible: true, multiQuantityEnabled: false },
      regionalPricingAndAvailabilityConfigs: regs,
      ...(other?.usdPrice && other?.eurPrice ? { newRegionsConfig: { usdPrice: other.usdPrice, eurPrice: other.eurPrice, availability: 'AVAILABLE' } } : {}),
    }],
  });
  const q = `allowMissing=true&updateMask=listings,purchaseOptions&regionsVersion.version=${encodeURIComponent(version)}&latencyTolerance=${LT}`;
  let r = await api(`/onetimeproducts/${p.sku}?${q}`, 'PATCH', product(regions));
  if (!r.ok) {
    console.log(`  (كل الدول: ${r.status} ${JSON.stringify(r.body).slice(0, 600)}) — نجرب السعودية بس`);
    r = await api(`/onetimeproducts/${p.sku}?${q}`, 'PATCH', product([{ regionCode: 'SA', price: money('SAR', p.sar), availability: 'AVAILABLE' }]));
  }
  if (!r.ok) { failed = true; console.log(`- ❌ ${p.sku}: ${r.status} ${JSON.stringify(r.body).slice(0, 800)}`); continue; }
  // تفعيل خيار الشراء
  const act = await api(`/onetimeproducts/${p.sku}/purchaseOptions:batchUpdateStates`, 'POST', {
    requests: [{ activatePurchaseOptionRequest: { packageName: PKG, productId: p.sku, purchaseOptionId: 'buy', latencyTolerance: LT } }],
  });
  if (act.ok) console.log(`- ✅ ${p.sku}: جاهز ومفعّل (${p.sar} ر.س، ${regions.length} دولة)`);
  else { failed = true; console.log(`- ⚠️ ${p.sku}: انضاف لكن التفعيل فشل: ${act.status} ${JSON.stringify(act.body).slice(0, 600)}`); }
}
if (failed) process.exit(1);
console.log('### ✅ باقات العملات جاهزة في Google Play');
