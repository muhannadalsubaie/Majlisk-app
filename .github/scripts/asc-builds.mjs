// حالة آخر النسخ المرفوعة إلى App Store Connect (قراءة فقط)
import { createPrivateKey, sign } from 'node:crypto';
import { readFileSync } from 'node:fs';
const b64u = (x) => Buffer.from(x).toString('base64url');
const now = Math.floor(Date.now() / 1000);
const head = b64u(JSON.stringify({ alg: 'ES256', kid: process.env.KEY_ID, typ: 'JWT' }));
const body = b64u(JSON.stringify({ iss: process.env.ISSUER, iat: now, exp: now + 900, aud: 'appstoreconnect-v1' }));
const sig = sign('sha256', Buffer.from(`${head}.${body}`), { key: createPrivateKey(readFileSync(process.env.KEY)), dsaEncoding: 'ieee-p1363' });
const jwt = `${head}.${body}.${b64u(sig)}`;
const api = async (path) => {
  const res = await fetch(`https://api.appstoreconnect.apple.com/v1/${path}`, { headers: { Authorization: `Bearer ${jwt}` } });
  const t = await res.text();
  if (!res.ok) throw new Error(`${path} → ${res.status}: ${t.slice(0, 400)}`);
  return JSON.parse(t);
};
const apps = await api('apps?filter[bundleId]=com.majlisk.app');
const app = apps.data[0];
console.log('app', app.id, app.attributes.name);
const builds = await api(`builds?filter[app]=${app.id}&sort=-uploadedDate&limit=6&include=buildBetaDetail`);
const details = Object.fromEntries((builds.included ?? []).map((d) => [d.id, d.attributes]));
for (const b of builds.data) {
  const d = details[b.relationships?.buildBetaDetail?.data?.id] ?? {};
  console.log(`build ${b.attributes.version} · ${b.attributes.processingState} · uploaded ${b.attributes.uploadedDate} · expired ${b.attributes.expired} · internal ${d.internalBuildState} · external ${d.externalBuildState}`);
}

// رفعات لم تصبح نسخاً (رفضتها Apple أثناء المعالجة) وسببها
try {
  const ups = await api(`buildUploads?filter[app]=${app.id}&limit=6&sort=-uploadedDate`);
  for (const u of ups.data) console.log('upload', JSON.stringify(u.attributes));
} catch (e) {
  try {
    const ups = await api(`apps/${app.id}/buildUploads?limit=6`);
    for (const u of ups.data) console.log('upload', JSON.stringify(u.attributes));
  } catch (e2) { console.log('buildUploads unavailable:', e2.message.slice(0, 300)); }
}
