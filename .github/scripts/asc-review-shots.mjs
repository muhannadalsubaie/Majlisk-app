// يرفع صور المراجعة (شاشة الشراء) لكل منتج في App Store Connect: العملات، هدية الباقة، والاشتراك الشهري.
// آبل تطلبها قبل ما ترسل المنتجات للمراجعة. ما يرفع أي نسخة.
import { createHash, createPrivateKey, sign } from 'node:crypto';
import { readFileSync } from 'node:fs';

const SHOTS = {
  coins_20: 'review-coins.png', coins_70: 'review-coins.png', coins_190: 'review-coins.png', coins_550: 'review-coins.png',
  pro_gift_1m: 'review-gift.png',
};
const SUB_SHOT = { pro_monthly: 'review-pro.png' };

const b64u = (x) => Buffer.from(x).toString('base64url');
const now = Math.floor(Date.now() / 1000);
const head = b64u(JSON.stringify({ alg: 'ES256', kid: process.env.KEY_ID, typ: 'JWT' }));
const body = b64u(JSON.stringify({ iss: process.env.ISSUER, iat: now, exp: now + 1200, aud: 'appstoreconnect-v1' }));
const sig = sign('sha256', Buffer.from(`${head}.${body}`), { key: createPrivateKey(readFileSync(process.env.KEY)), dsaEncoding: 'ieee-p1363' });
const jwt = `${head}.${body}.${b64u(sig)}`;
const api = async (path, method = 'GET', data) => {
  const url = `https://api.appstoreconnect.apple.com/${path.startsWith('v2/') ? '' : 'v1/'}${path}`;
  const res = await fetch(url, { method, headers: { Authorization: `Bearer ${jwt}`, 'Content-Type': 'application/json' }, body: data ? JSON.stringify(data) : undefined });
  const t = await res.text();
  if (!res.ok) throw new Error(`${method} ${path} → ${res.status}: ${t.slice(0, 500)}`);
  return t ? JSON.parse(t) : {};
};
const all = async (path) => {
  const out = [];
  let next = path;
  while (next) { const r = await api(next.replace('https://api.appstoreconnect.apple.com/v1/', '').replace('https://api.appstoreconnect.apple.com/', '')); out.push(...(r.data ?? [])); next = r.links?.next ?? null; }
  return out;
};

/** يحجز الصورة، يرفعها بالأجزاء اللي تطلبها آبل، ويأكدها */
async function upload(type, relName, relType, relId, file) {
  const bytes = readFileSync(`.github/assets/${file}`);
  const r = await api(type, 'POST', { data: { type, attributes: { fileName: file, fileSize: bytes.length }, relationships: { [relName]: { data: { type: relType, id: relId } } } } });
  for (const op of r.data.attributes.uploadOperations ?? []) {
    const headers = Object.fromEntries((op.requestHeaders ?? []).map((h) => [h.name, h.value]));
    const res = await fetch(op.url, { method: op.method, headers, body: bytes.subarray(op.offset, op.offset + op.length) });
    if (!res.ok) throw new Error(`upload part → ${res.status}`);
  }
  const md5 = createHash('md5').update(bytes).digest('hex');
  await api(`${type}/${r.data.id}`, 'PATCH', { data: { type, id: r.data.id, attributes: { uploaded: true, sourceFileChecksum: md5 } } });
}

let failed = false;
const app = (await api('apps?filter[bundleId]=com.majlisk.app')).data[0];
const iaps = await all(`apps/${app.id}/inAppPurchasesV2?limit=200`);
for (const [pid, file] of Object.entries(SHOTS)) {
  try {
    const iap = iaps.find((x) => x.attributes.productId === pid);
    if (!iap) throw new Error('المنتج غير موجود');
    const cur = await api(`v2/inAppPurchases/${iap.id}/appStoreReviewScreenshot`).catch(() => ({}));
    if (cur.data?.id) await api(`inAppPurchaseAppStoreReviewScreenshots/${cur.data.id}`, 'DELETE').catch(() => {});
    await upload('inAppPurchaseAppStoreReviewScreenshots', 'inAppPurchaseV2', 'inAppPurchases', iap.id, file);
    const state = (await api(`v2/inAppPurchases/${iap.id}`)).data.attributes.state;
    console.log(`- ✅ ${pid}: انرفعت الصورة · ${state}`);
  } catch (e) { failed = true; console.log(`- ❌ ${pid}: ${e.message}`); }
}
const groups = await all(`apps/${app.id}/subscriptionGroups?limit=50`);
for (const g of groups) {
  for (const s of await all(`subscriptionGroups/${g.id}/subscriptions?limit=50`)) {
    const file = SUB_SHOT[s.attributes.productId];
    if (!file) continue;
    try {
      const cur = await api(`subscriptions/${s.id}/appStoreReviewScreenshot`).catch(() => ({}));
      if (cur.data?.id) await api(`subscriptionAppStoreReviewScreenshots/${cur.data.id}`, 'DELETE').catch(() => {});
      await upload('subscriptionAppStoreReviewScreenshots', 'subscription', 'subscriptions', s.id, file);
      const state = (await api(`subscriptions/${s.id}`)).data.attributes.state;
      console.log(`- ✅ ${s.attributes.productId}: انرفعت الصورة · ${state}`);
    } catch (e) { failed = true; console.log(`- ❌ ${s.attributes.productId}: ${e.message}`); }
  }
}
if (failed) process.exit(1);
console.log('### ✅ صور المراجعة انرفعت لكل المنتجات');
