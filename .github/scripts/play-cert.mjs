// بصمة مفتاح توقيع Google Play (قراءة فقط): تنزّل النسخة العامة اللي وقّعتها Google لآخر إصدار وتطبع بصمتها
import { createSign } from 'node:crypto';
import { writeFileSync } from 'node:fs';
import { execSync } from 'node:child_process';
import { fixKey } from './play-key.mjs';
const sa = fixKey(process.env.SA || '{}');
const b64u = (x) => Buffer.from(x).toString('base64url');
const now = Math.floor(Date.now() / 1000);
const unsigned = `${b64u(JSON.stringify({ alg: 'RS256', typ: 'JWT' }))}.${b64u(JSON.stringify({ iss: sa.client_email, scope: 'https://www.googleapis.com/auth/androidpublisher', aud: sa.token_uri, iat: now, exp: now + 600 }))}`;
const sig = createSign('RSA-SHA256').update(unsigned).sign(sa.private_key, 'base64url');
const tok = (await (await fetch(sa.token_uri, { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${unsigned}.${sig}` })).json()).access_token;
const base = 'https://androidpublisher.googleapis.com/androidpublisher/v3/applications/com.majlisk.app';
const auth = { Authorization: `Bearer ${tok}` };
const vc = process.env.VC || '10067';
const r = await fetch(`${base}/generatedApks/${vc}`, { headers: auth });
const j = await r.json();
if (!r.ok) { console.log(`### ❌ ${JSON.stringify(j).slice(0, 400)}`); process.exit(1); }
const g = j.generatedApks?.[0];
console.log(`certificateSha256Hash: ${g?.certificateSha256Hash}`);
const id = g?.generatedUniversalApk?.downloadId;
if (!id) { console.log('no universal apk'); process.exit(0); }
const apk = await fetch(`${base}/generatedApks/${vc}/downloads/${encodeURIComponent(id)}:download?alt=media`, { headers: auth });
if (!apk.ok) { console.log(`### ❌ download ${apk.status}`); process.exit(1); }
writeFileSync('/tmp/u.apk', Buffer.from(await apk.arrayBuffer()));
const bt = execSync('ls -d $ANDROID_HOME/build-tools/* | sort -V | tail -1').toString().trim();
const out = execSync(`${bt}/apksigner verify --print-certs /tmp/u.apk`).toString();
for (const l of out.split('\n')) if (/SHA-1|SHA-256/.test(l)) console.log(`### ${l.replace(/^.*(SHA-\d+)[^:]*:\s*/, '$1: ').toUpperCase().replace(/(..)(?=.)/g, '$1:')}`);
