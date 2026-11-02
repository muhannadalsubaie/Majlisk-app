// بعد رفع نسخة الآيفون: ننتظر لين تخلص Apple معالجتها، ثم نضيفها لمجموعة المختبرين الخارجيين
// (رابط TestFlight العام) ونرسلها لمراجعة الاختبار، فيوصل التحديث للمختبرين بلا أي خطوة يدوية.
// المتغيرات: KEY (ملف المفتاح)، KEY_ID، ISSUER، BUILD (رقم النسخة)، NOTES (ملف "وش الجديد"، اختياري)
import { createPrivateKey, sign } from 'node:crypto';
import { existsSync, readFileSync } from 'node:fs';

const b64u = (x) => Buffer.from(x).toString('base64url');
const key = createPrivateKey(readFileSync(process.env.KEY));
// توكن جديد لكل طلب: الانتظار قد يطول أكثر من عمر التوكن (٢٠ دقيقة)
function jwt() {
  const now = Math.floor(Date.now() / 1000);
  const head = b64u(JSON.stringify({ alg: 'ES256', kid: process.env.KEY_ID, typ: 'JWT' }));
  const body = b64u(JSON.stringify({ iss: process.env.ISSUER, iat: now, exp: now + 900, aud: 'appstoreconnect-v1' }));
  const sig = sign('sha256', Buffer.from(`${head}.${body}`), { key, dsaEncoding: 'ieee-p1363' });
  return `${head}.${body}.${b64u(sig)}`;
}
async function api(path, method = 'GET', data) {
  const res = await fetch(`https://api.appstoreconnect.apple.com/v1/${path}`, {
    method,
    headers: { Authorization: `Bearer ${jwt()}`, 'Content-Type': 'application/json' },
    body: data ? JSON.stringify(data) : undefined,
  });
  const t = await res.text();
  if (!res.ok) throw new Error(`${method} ${path} → ${res.status}: ${t.slice(0, 500)}`);
  return t ? JSON.parse(t) : {};
}
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const log = (s) => console.log(s);

const BUILD = process.env.BUILD;
const app = (await api('apps?filter[bundleId]=com.majlisk.app')).data[0];
if (!app) throw new Error('app not found');

// ١) ننتظر النسخة لين تصير جاهزة (المعالجة عادة ٥–٣٠ دقيقة)
let build = null;
for (let i = 0; i < 60; i++) {
  const r = await api(`builds?filter[app]=${app.id}&filter[version]=${BUILD}&limit=1`);
  build = r.data[0] ?? null;
  const state = build?.attributes.processingState;
  log(`build ${BUILD}: ${state ?? 'not yet visible'}`);
  if (state === 'VALID') break;
  if (state === 'FAILED' || state === 'INVALID') throw new Error(`build ${BUILD} processing ${state}`);
  await sleep(60_000);
}
if (build?.attributes.processingState !== 'VALID') throw new Error(`build ${BUILD} not processed in time`);

// التشفير: التطبيق ما يستخدم تشفير خاص (لو ما انقرأ من الإعدادات)
if (build.attributes.usesNonExemptEncryption == null) {
  await api(`builds/${build.id}`, 'PATCH', { data: { type: 'builds', id: build.id, attributes: { usesNonExemptEncryption: false } } }).catch((e) => log(`encryption: ${e.message}`));
}

// ٢) "وش الجديد" للمختبرين (من سجل التحديثات)
const notes = process.env.NOTES && existsSync(process.env.NOTES) ? readFileSync(process.env.NOTES, 'utf8').trim().slice(0, 3900) : '';
if (notes) {
  try {
    const locs = await api(`builds/${build.id}/betaBuildLocalizations`);
    if (locs.data.length) {
      for (const l of locs.data) await api(`betaBuildLocalizations/${l.id}`, 'PATCH', { data: { type: 'betaBuildLocalizations', id: l.id, attributes: { whatsNew: notes } } });
    } else {
      await api('betaBuildLocalizations', 'POST', { data: { type: 'betaBuildLocalizations', attributes: { locale: 'ar-SA', whatsNew: notes }, relationships: { build: { data: { type: 'builds', id: build.id } } } } });
    }
    log('whats new: set');
  } catch (e) { log(`whats new: ${e.message}`); }
}

// ٣) نضيفها لكل مجموعة مختبرين خارجيين (فيها الرابط العام)
const groups = (await api(`betaGroups?filter[app]=${app.id}&filter[isInternalGroup]=false&limit=50`)).data;
if (!groups.length) throw new Error('no external tester group');
for (const g of groups) {
  await api(`betaGroups/${g.id}/relationships/builds`, 'POST', { data: [{ type: 'builds', id: build.id }] });
  log(`added to group: ${g.attributes.name}`);
}

// ٤) نرسلها لمراجعة الاختبار (بعد أول موافقة غالباً تنقبل تلقائياً)
try {
  const r = await api('betaAppReviewSubmissions', 'POST', { data: { type: 'betaAppReviewSubmissions', relationships: { build: { data: { type: 'builds', id: build.id } } } } });
  log(`submitted for beta review: ${r.data?.attributes?.betaReviewState ?? 'ok'}`);
} catch (e) {
  // سبق إرسالها أو انقبلت تلقائياً
  log(`beta review: ${e.message}`);
}
console.log(`### النسخة ${BUILD} أُضيفت لمختبرين TestFlight الخارجيين (الرابط العام) وأُرسلت للمراجعة`);
