package com.majlisk.app.data

/** نفس قواعد أسماء المستخدمين في الخادم (shared/username.ts) — القرار النهائي في الخادم */
object Usernames {
    const val MIN = 3
    const val MAX = 16
    private val ALLOWED = Regex("^[ء-غف-يa-zA-Z0-9٠-٩_]+$")

    val ERRORS = mapOf(
        "too-short" to "اسم المستخدم قصير — $MIN أحرف على الأقل",
        "too-long" to "اسم المستخدم طويل — $MAX حرفاً كحد أقصى",
        "invalid-chars" to "استخدم حروفاً عربية أو إنجليزية أو أرقاماً أو _ فقط، بدون مسافات",
        "only-underscores" to "يجب أن يحتوي اسم المستخدم على حرف أو رقم",
        "taken" to "اسم المستخدم مأخوذ، جرّب اسماً آخر",
        "already-set" to "لديك اسم مستخدم مسبقاً",
    )

    fun clean(raw: String) = raw.trim().replace(Regex("[\u064B-\u065F\u0670\u0640]"), "")

    fun validate(raw: String): String? {
        val name = clean(raw)
        val n = name.codePointCount(0, name.length)
        return when {
            n < MIN -> "too-short"
            n > MAX -> "too-long"
            !ALLOWED.matches(name) -> "invalid-chars"
            name.all { it == '_' } -> "only-underscores"
            else -> null
        }
    }
}
