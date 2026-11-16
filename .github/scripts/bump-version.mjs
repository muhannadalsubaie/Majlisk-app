// بعد ما تنرفع نسخة جديدة للمتجر: نحدّث version.json (التطبيق يقراه ويطلع للاعب «تحديث جديد»)
// node .github/scripts/bump-version.mjs android 10234
import { readFileSync, writeFileSync } from 'node:fs';
import { execSync } from 'node:child_process';
const [platform, buildRaw] = process.argv.slice(2);
const build = Number(buildRaw);
if (!['android', 'ios'].includes(platform) || !Number.isInteger(build) || build <= 0) { console.log('usage: bump-version.mjs android|ios <build>'); process.exit(1); }
const sh = (c) => execSync(c, { stdio: 'inherit' });
sh('git config user.name "github-actions[bot]" && git config user.email "41898282+github-actions[bot]@users.noreply.github.com"');
for (let attempt = 1; attempt <= 5; attempt++) {
  sh('git fetch -q origin main && git reset -q --hard origin/main');
  const v = JSON.parse(readFileSync('version.json', 'utf8'));
  if ((v[platform]?.build ?? 0) >= build) { console.log(`version.json ${platform} already ${v[platform].build}`); process.exit(0); }
  v[platform] = { ...(v[platform] ?? {}), build };
  writeFileSync('version.json', JSON.stringify(v, null, 1) + '\n');
  sh(`git add version.json && git commit -q -m "${platform} ${build}: نسخة جديدة في المتجر [skip ci]"`);
  try { sh('git push -q origin HEAD:main'); console.log(`version.json ${platform} = ${build}`); process.exit(0); } catch { console.log(`push retry ${attempt}`); }
}
process.exit(1);
