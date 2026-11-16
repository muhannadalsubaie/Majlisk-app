// بعد ما تنرفع نسخة جديدة للمتجر: نبلّغ الخادم برقمها (التطبيق يسأل الخادم ويطلع للاعب «تحديث جديد»)
// SA=<مفتاح حساب خدمة Google Play> node .github/scripts/bump-version.mjs android 10234
import { createPrivateKey, createSign } from 'node:crypto';
import { fixKey } from './play-key.mjs';
const [platform, buildRaw] = process.argv.slice(2);
const build = Number(buildRaw);
if (!['android', 'ios'].includes(platform) || !Number.isInteger(build) || build <= 0) { console.log('usage: bump-version.mjs android|ios <build>'); process.exit(1); }
const sa = fixKey(process.env.SA || '{}');
const b64u = (x) => Buffer.from(x).toString('base64url');
const now = Math.floor(Date.now() / 1000);
const unsigned = `${b64u(JSON.stringify({ alg: 'RS256', typ: 'JWT' }))}.${b64u(JSON.stringify({ iss: sa.client_email, scope: 'https://www.googleapis.com/auth/userinfo.email', aud: 'https://oauth2.googleapis.com/token', iat: now, exp: now + 600 }))}`;
const sig = createSign('RSA-SHA256').update(unsigned).sign(createPrivateKey(sa.private_key), 'base64url');
const tok = (await (await fetch('https://oauth2.googleapis.com/token', { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${unsigned}.${sig}` })).json()).access_token;
const res = await fetch('https://majlisk-api.majlisk.workers.dev/api/admin/app-version', {
  method: 'POST', headers: { Authorization: `Bearer ${tok}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ platform, build }),
});
console.log(`app-version ${platform} ${build}: ${res.status}`);
if (!res.ok) process.exit(1);
