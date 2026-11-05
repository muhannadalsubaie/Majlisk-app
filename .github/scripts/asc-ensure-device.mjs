// التوقيع التلقائي في Xcode يحتاج جهازاً واحداً مسجلاً على الأقل في حساب Apple لإنشاء ملفات التوقيع،
// حتى عند الرفع إلى TestFlight فقط. إن لم يوجد أي جهاز نسجّل جهازاً بديلاً عبر App Store Connect API.
// وكل بناء يعمل على جهاز ماك جديد: شهادة التطوير التي أنشأها بناء سابق مفتاحها ليس هنا، فنلغيها
// ليُنشئ Xcode شهادة جديدة (التوقيع للمتجر نفسه تديره Apple سحابياً ولا يتأثر). وافق صاحب الحساب على ذلك.
// المتغيرات: KEY (مسار ملف p8)، KEY_ID، ISSUER
import { createPrivateKey, randomBytes, sign } from 'node:crypto';
import { readFileSync } from 'node:fs';

const b64u = (x) => Buffer.from(x).toString('base64url');
const now = Math.floor(Date.now() / 1000);
const head = b64u(JSON.stringify({ alg: 'ES256', kid: process.env.KEY_ID, typ: 'JWT' }));
const body = b64u(JSON.stringify({ iss: process.env.ISSUER, iat: now, exp: now + 900, aud: 'appstoreconnect-v1' }));
const sig = sign('sha256', Buffer.from(`${head}.${body}`), { key: createPrivateKey(readFileSync(process.env.KEY)), dsaEncoding: 'ieee-p1363' });
const jwt = `${head}.${body}.${b64u(sig)}`;
const api = async (path, init = {}) => {
  const res = await fetch(`https://api.appstoreconnect.apple.com/v1/${path}`, {
    ...init, headers: { Authorization: `Bearer ${jwt}`, 'Content-Type': 'application/json' },
  });
  const text = await res.text();
  if (!res.ok) throw new Error(`${init.method ?? 'GET'} ${path} → ${res.status}: ${text.slice(0, 500)}`);
  return text ? JSON.parse(text) : {};
};

const list = await api('devices?filter[platform]=IOS&filter[status]=ENABLED&limit=1');
if (list.data.length) {
  console.log('device already registered:', list.data[0].attributes.name);
} else {
  const udid = `00008030-${randomBytes(8).toString('hex').toUpperCase()}`;
  const r = await api('devices', {
    method: 'POST',
    body: JSON.stringify({ data: { type: 'devices', attributes: { name: 'CI build placeholder', platform: 'IOS', udid } } }),
  });
  console.log('registered placeholder device:', r.data.attributes.name);
}

// شهادات التطوير القديمة (أنشأتها بناءات سابقة على أجهزة لم تعد موجودة)
const certs = await api('certificates?filter[certificateType]=DEVELOPMENT,IOS_DEVELOPMENT&limit=200');
for (const c of certs.data) {
  await api(`certificates/${c.id}`, { method: 'DELETE' });
  console.log('revoked old development certificate:', c.attributes.name ?? c.id);
}

// الإشعارات (دعوات الأصدقاء): نفعّل خاصية Push Notifications لمعرّف التطبيق إن لم تكن مفعّلة،
// ونحذف ملفات توقيع المتجر القديمة اللي ما فيها الخاصية، فيُنشئ Xcode ملفات جديدة تشملها.
const bundles = await api('bundleIds?filter[identifier]=com.majlisk.app&limit=5');
const bundle = bundles.data.find((b) => b.attributes.identifier === 'com.majlisk.app');
if (bundle) {
  const caps = await api(`bundleIds/${bundle.id}/bundleIdCapabilities`);
  if (!caps.data.some((c) => c.attributes.capabilityType === 'PUSH_NOTIFICATIONS')) {
    await api('bundleIdCapabilities', {
      method: 'POST',
      body: JSON.stringify({ data: { type: 'bundleIdCapabilities', attributes: { capabilityType: 'PUSH_NOTIFICATIONS' }, relationships: { bundleId: { data: { type: 'bundleIds', id: bundle.id } } } } }),
    });
    console.log('enabled push notifications capability');
    const profiles = await api(`bundleIds/${bundle.id}/profiles?limit=50`);
    for (const p of profiles.data) {
      await api(`profiles/${p.id}`, { method: 'DELETE' }).catch((e) => console.log('profile', e.message));
      console.log('deleted old profile:', p.attributes.name);
    }
  } else console.log('push notifications capability already enabled');
} else console.log('bundle id not found');
