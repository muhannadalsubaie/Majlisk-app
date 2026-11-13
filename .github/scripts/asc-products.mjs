// ينشئ (أو يكمّل) منتجات الشراء في App Store Connect: باقات العملات، هدية الباقة الاحترافية،
// والاشتراك الشهري للباقة الاحترافية — نفس معرّفات Google Play. ما يرفع أي نسخة.
import { createPrivateKey, sign } from 'node:crypto';
import { readFileSync } from 'node:fs';

const PACKS = [
  { id: 'coins_20', sar: 3.99, name: '20 عملة', desc: '20 عملة للعب في مجلسك' },
  { id: 'coins_70', sar: 9.99, name: '80 عملة', desc: '70 عملة + 10 هدية' },
  { id: 'coins_190', sar: 19.99, name: '230 عملة', desc: '190 عملة + 40 هدية' },
  { id: 'coins_550', sar: 44.99, name: '700 عملة', desc: '550 عملة + 150 هدية' },
  { id: 'pro_gift_1m', sar: 11.5, name: 'هدية الباقة الاحترافية', desc: 'شهر من الباقة الاحترافية للاعب ثاني' },
];
const SUB = { id: 'pro_monthly', sar: 11.5, name: 'الباقة الاحترافية', desc: 'كل مزايا مجلسك في اشتراك شهري', group: 'الباقة الاحترافية' };
const LOCALE = 'ar-SA';
const BASE = 'SAU';

const b64u = (x) => Buffer.from(x).toString('base64url');
const now = Math.floor(Date.now() / 1000);
const head = b64u(JSON.stringify({ alg: 'ES256', kid: process.env.KEY_ID, typ: 'JWT' }));
const body = b64u(JSON.stringify({ iss: process.env.ISSUER, iat: now, exp: now + 1200, aud: 'appstoreconnect-v1' }));
const sig = sign('sha256', Buffer.from(`${head}.${body}`), { key: createPrivateKey(readFileSync(process.env.KEY)), dsaEncoding: 'ieee-p1363' });
const jwt = `${head}.${body}.${b64u(sig)}`;

const api = async (path, method = 'GET', data) => {
  const url = path.startsWith('http') ? path : `https://api.appstoreconnect.apple.com/${path.startsWith('v2/') ? '' : 'v1/'}${path}`;
  const res = await fetch(url, { method, headers: { Authorization: `Bearer ${jwt}`, 'Content-Type': 'application/json' }, body: data ? JSON.stringify(data) : undefined });
  const t = await res.text();
  if (!res.ok) throw new Error(`${method} ${path} → ${res.status}: ${t.slice(0, 600)}`);
  return t ? JSON.parse(t) : {};
};
/** كل الصفحات */
const all = async (path) => {
  const out = [];
  let next = path;
  while (next) { const r = await api(next); out.push(...(r.data ?? [])); next = r.links?.next ?? null; }
  return out;
};
const rel = (type, id) => ({ data: { type, id } });
/** أقرب نقطة سعر للسعر المطلوب بالريال */
const closest = (points, sar) => points.reduce((a, b) => (Math.abs(Number(b.attributes.customerPrice) - sar) < Math.abs(Number(a.attributes.customerPrice) - sar) ? b : a));

let failed = false;
const app = (await api('apps?filter[bundleId]=com.majlisk.app')).data[0];
console.log(`app ${app.id} ${app.attributes.name}`);
const territories = (await all('territories?limit=200')).map((t) => ({ type: 'territories', id: t.id }));

// ───── منتجات تُشترى مرة وحدة (Consumable) ─────
const existing = await all(`apps/${app.id}/inAppPurchasesV2?limit=200`);
for (const p of PACKS) {
  try {
    let iap = existing.find((x) => x.attributes.productId === p.id);
    if (!iap) {
      iap = (await api('v2/inAppPurchases', 'POST', { data: { type: 'inAppPurchases', attributes: { name: p.name, productId: p.id, inAppPurchaseType: 'CONSUMABLE', reviewNote: p.desc }, relationships: { app: rel('apps', app.id) } } })).data;
      console.log(`  + أنشأت ${p.id}`);
    }
    // الاسم والوصف بالعربي
    const locs = await all(`v2/inAppPurchases/${iap.id}/inAppPurchaseLocalizations?limit=50`);
    if (!locs.some((l) => l.attributes.locale === LOCALE)) {
      await api('inAppPurchaseLocalizations', 'POST', { data: { type: 'inAppPurchaseLocalizations', attributes: { locale: LOCALE, name: p.name, description: p.desc }, relationships: { inAppPurchaseV2: rel('inAppPurchases', iap.id) } } });
    }
    // السعر بالريال، وباقي الدول تتحول تلقائياً
    const points = await all(`v2/inAppPurchases/${iap.id}/pricePoints?filter[territory]=${BASE}&limit=200`);
    const pp = closest(points, p.sar);
    await api('inAppPurchasePriceSchedules', 'POST', {
      data: { type: 'inAppPurchasePriceSchedules', relationships: { inAppPurchase: rel('inAppPurchases', iap.id), baseTerritory: rel('territories', BASE), manualPrices: { data: [{ type: 'inAppPurchasePrices', id: '${price}' }] } } },
      included: [{ type: 'inAppPurchasePrices', id: '${price}', attributes: { startDate: null }, relationships: { inAppPurchasePricePoint: rel('inAppPurchasePricePoints', pp.id) } }],
    });
    // متاح في كل الدول
    try {
      await api('inAppPurchaseAvailabilities', 'POST', { data: { type: 'inAppPurchaseAvailabilities', attributes: { availableInNewTerritories: true }, relationships: { inAppPurchase: rel('inAppPurchases', iap.id), availableTerritories: { data: territories } } } });
    } catch (e) { if (!/409/.test(e.message)) throw e; }
    const state = (await api(`v2/inAppPurchases/${iap.id}`)).data.attributes.state;
    console.log(`- ✅ ${p.id}: ${pp.attributes.customerPrice} ر.س · ${state}`);
  } catch (e) { failed = true; console.log(`- ❌ ${p.id}: ${e.message}`); }
}

// ───── الاشتراك الشهري ─────
try {
  const groups = await all(`apps/${app.id}/subscriptionGroups?limit=50`);
  let group = groups.find((g) => g.attributes.referenceName === SUB.group);
  if (!group) {
    group = (await api('subscriptionGroups', 'POST', { data: { type: 'subscriptionGroups', attributes: { referenceName: SUB.group }, relationships: { app: rel('apps', app.id) } } })).data;
    console.log('  + أنشأت مجموعة الاشتراك');
  }
  const gLocs = await all(`subscriptionGroups/${group.id}/subscriptionGroupLocalizations?limit=50`);
  if (!gLocs.some((l) => l.attributes.locale === LOCALE)) {
    await api('subscriptionGroupLocalizations', 'POST', { data: { type: 'subscriptionGroupLocalizations', attributes: { locale: LOCALE, name: SUB.group }, relationships: { subscriptionGroup: rel('subscriptionGroups', group.id) } } });
  }
  const subs = await all(`subscriptionGroups/${group.id}/subscriptions?limit=50`);
  let sub = subs.find((s) => s.attributes.productId === SUB.id);
  if (!sub) {
    sub = (await api('subscriptions', 'POST', { data: { type: 'subscriptions', attributes: { name: SUB.name, productId: SUB.id, subscriptionPeriod: 'ONE_MONTH', familySharable: false, groupLevel: 1, reviewNote: SUB.desc }, relationships: { group: rel('subscriptionGroups', group.id) } } })).data;
    console.log('  + أنشأت الاشتراك');
  }
  const sLocs = await all(`subscriptions/${sub.id}/subscriptionLocalizations?limit=50`);
  if (!sLocs.some((l) => l.attributes.locale === LOCALE)) {
    await api('subscriptionLocalizations', 'POST', { data: { type: 'subscriptionLocalizations', attributes: { locale: LOCALE, name: SUB.name, description: SUB.desc }, relationships: { subscription: rel('subscriptions', sub.id) } } });
  }
  try {
    await api('subscriptionAvailabilities', 'POST', { data: { type: 'subscriptionAvailabilities', attributes: { availableInNewTerritories: true }, relationships: { subscription: rel('subscriptions', sub.id), availableTerritories: { data: territories } } } });
  } catch (e) { if (!/409/.test(e.message)) throw e; }
  // السعر: السعودية، وكل دولة بالسعر المكافئ اللي تقترحه Apple
  const points = await all(`subscriptions/${sub.id}/pricePoints?filter[territory]=${BASE}&limit=200`);
  const pp = closest(points, SUB.sar);
  const eq = await all(`subscriptionPricePoints/${pp.id}/equalizations?limit=200&include=territory`);
  const setPrice = async (pointId, territory) => api('subscriptionPrices', 'POST', {
    data: { type: 'subscriptionPrices', attributes: { startDate: null, preserveCurrentPrice: false }, relationships: { subscription: rel('subscriptions', sub.id), subscriptionPricePoint: rel('subscriptionPricePoints', pointId), territory: rel('territories', territory) } },
  });
  await setPrice(pp.id, BASE);
  let ok = 1, bad = 0;
  for (const e of eq) {
    const t = e.relationships?.territory?.data?.id;
    if (!t || t === BASE) continue;
    try { await setPrice(e.id, t); ok++; } catch { bad++; }
  }
  const state = (await api(`subscriptions/${sub.id}`)).data.attributes.state;
  console.log(`- ✅ ${SUB.id}: اشتراك شهري ${pp.attributes.customerPrice} ر.س · أسعار ${ok} دولة${bad ? ` (تعذّر ${bad})` : ''} · ${state}`);
} catch (e) { failed = true; console.log(`- ❌ ${SUB.id}: ${e.message}`); }

if (failed) process.exit(1);
console.log('### ✅ منتجات App Store جاهزة (تنرسل للمراجعة مع أول نسخة فيها شاشة الشراء)');
