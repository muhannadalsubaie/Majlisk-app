// يصلّح ملف مفتاح Google Play لو انلصق من الجوال وتحولت "\n" داخل المفتاح لأسطر حقيقية:
// نحوّل أي حرف تحكم داخل النصوص إلى صيغته الصحيحة. يكتب الناتج في المسار المعطى (أو يطبعه)
import { writeFileSync } from 'node:fs';
export function fixKey(raw) {
  let out = '', inStr = false, esc = false;
  for (const ch of raw.trim()) {
    if (inStr) {
      if (esc) { esc = false; out += ch; continue; }
      if (ch === '\\') { esc = true; out += ch; continue; }
      if (ch === '"') { inStr = false; out += ch; continue; }
      if (ch === '\n') { out += '\\n'; continue; }
      if (ch === '\r') continue;
      if (ch === '\t') { out += '\\t'; continue; }
      out += ch;
    } else {
      if (ch === '"') inStr = true;
      out += ch;
    }
  }
  const sa = JSON.parse(out);
  // سطور المفتاح لازم تكون مفصولة صح (لو انلصقت بمسافات بدل أسطر)
  sa.private_key = sa.private_key.replace(/-----BEGIN PRIVATE KEY-----\s*/, '-----BEGIN PRIVATE KEY-----\n').replace(/\s*-----END PRIVATE KEY-----\s*/, '\n-----END PRIVATE KEY-----\n');
  return sa;
}
if (process.argv[2]) writeFileSync(process.argv[2], JSON.stringify(fixKey(process.env.SA || '{}')), { mode: 0o600 });
