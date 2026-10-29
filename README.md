# مجلسك — تطبيقات الجوال الأصلية

تطبيقا مجلسك الأصليان:
- **iOS** بلغة Swift (SwiftUI)
- **Android** بلغة Kotlin (Jetpack Compose)

يتصلان بخادم مجلسك (Cloudflare) نفسه، فالقوانين والطاولات والعملات والحسابات مشتركة.

## التوقيع والنشر
الأسرار في إعدادات GitHub (Settings ← Secrets and variables ← Actions):
`APPLE_TEAM_ID`، `ASC_KEY_ID`، `ASC_ISSUER_ID`، `ASC_KEY_P8`، `ANDROID_KEYSTORE_PASSWORD`.

`android/keystore/upload.jks.enc` مفتاح توقيع الأندرويد مشفّراً بـ `ANDROID_KEYSTORE_PASSWORD`
(نفس مفتاح التطبيق الحالي، حتى تُثبَّت النسخة الجديدة فوق القديمة مباشرة).
