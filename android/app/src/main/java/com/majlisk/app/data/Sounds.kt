package com.majlisk.app.data

import android.content.Context
import android.media.AudioAttributes
import android.media.SoundPool
import android.os.Handler
import android.os.Looper
import kotlin.random.Random

/**
 * مؤثرات اللعبة (حزم Kenney، رخصة CC0) — نفس أصوات التطبيق الحالي وتوقيتها.
 * تحترم "كتم عام لجميع الأصوات"، ومعتدلة حتى لا تغطي قارئ الشاشة.
 */
object Sounds {
    /** الوقت بين طقطقة كل خطوة يمشيها الحجر (نفس مهلة الخادم: الدور ما ينتقل لين يوصل الحجر) */
    const val STEP_GAP = 0.22
    /** أصوات اللعبة العادية، ونسخة منها على قناة المكالمات (وقت المحادثة الصوتية) */
    private lateinit var gamePool: SoundPool
    private lateinit var callPool: SoundPool
    private val gameIds = HashMap<String, Int>()
    private val callIds = HashMap<String, Int>()
    /** وقت المحادثة الصوتية: أصوات اللعبة على قناة المكالمات، بنفس مستوى أصوات اللاعبين،
     *  وإلغاء الصدى في الجوال يلغيها من الميكروفون فما يسمعها الباقين منك */
    @Volatile private var inCall = false
    private val pool get() = if (inCall) callPool else gamePool
    private val ids get() = if (inCall) callIds else gameIds
    fun callMode(on: Boolean) { inCall = on }
    private val main = Handler(Looper.getMainLooper())
    private val recent = HashMap<String, Long>()

    private val FILES = listOf(
        "card1", "card2", "card3", "card4",
        "shove1", "shove2", "shove3", "shove4", "shuffle", "fan", "chips1", "chips2", "collide",
        "knock1", "cup1", "trick-collect", "chips3", "chips4", "chips5", "chips6",
        "collide2", "collide3", "collide4", "lay1", "lay2", "handle1", "match-win", "match-lose", "kaboot", "bid",
        "app-open", "table-join", "table-leave", "proj-sira", "proj-fifty", "bid-sun", "voice-join", "voice-leave",
        "voice-pass", "voice-wala", "voice-sun", "voice-hokm", "voice-hokm2", "voice-ashkal",
        "voice-double", "voice-three", "voice-four", "voice-gahwa", "voice-locked", "voice-open", "voice-turn", "voice-qablak", "proj-hundred", "proj-400",
        "voice-confirm", "voice-hokm2-S", "voice-hokm2-H", "voice-hokm2-C", "voice-hokm2-D", "mic-on", "mic-off",
        "domino-shuffle", "domino-tile", "dice", "step1", "step2", "marble1", "marble2", "deal", "capture", "jackaroo-card", "voice-first", "voice-second", "voice-paper", "voice-sawa", "voice-ekka", "domino-end", "proj-baloot", "trump-cut", "hand-end",
        "illegal", "voice-invite", "invite-in", "notify", "join-request", "chat-msg", "jk-home", "ludo-home", "jk-back", "jk-swap", "proj-reveal",
    ) + (1..13).flatMap { listOf("steps-$it", "marbles-$it") }
    private val loaded = HashSet<Int>()
    private var openPending = false

    fun init(c: Context) {
        gamePool = SoundPool.Builder().setMaxStreams(8).setAudioAttributes(
            AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_GAME).setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build(),
        ).build()
        callPool = SoundPool.Builder().setMaxStreams(8).setAudioAttributes(
            AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION).setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build(),
        ).build()
        val pool = gamePool
        val ids = gameIds
        // نغمة الفتح قد تُطلب قبل اكتمال تحميلها: تُشغَّل لحظة جاهزيتها
        pool.setOnLoadCompleteListener { p, id, status ->
            if (status != 0) return@setOnLoadCompleteListener
            loaded += id
            if (openPending && id == ids["app-open"]) { openPending = false; if (!Prefs.muted) p.play(id, 0.8f, 0.8f, 1, 0, 1f) }
        }
        for (name in FILES) {
            runCatching { c.assets.openFd("sounds/$name.mp3").use { ids[name] = pool.load(it, 1) } }
            runCatching { c.assets.openFd("sounds/$name.mp3").use { callIds[name] = callPool.load(it, 1) } }
        }
    }

    private fun play(name: String, at: Double = 0.0, gain: Float = 0.8f, rate: Float = 1f, vary: Boolean = true) {
        if (Prefs.muted) return
        val id = ids[name] ?: return
        val r = (rate * if (vary) 0.95f + Random.nextFloat() * 0.1f else 1f).coerceIn(0.5f, 2f)
        val run = Runnable { pool.play(id, gain, gain, 1, 0, r) }
        if (at <= 0) run.run() else main.postDelayed(run, (at * 1000).toLong())
    }

    private fun pick(vararg names: String) = names[Random.nextInt(names.size)]

    /** صوت المزايدة يُشغَّل فوراً عند ضغطة صاحبه، ثم يصل التحديث من الخادم: لا نكرره */
    private fun once(kind: String): Boolean {
        val now = System.currentTimeMillis()
        if (now - (recent[kind] ?: 0) < 2500) return false
        recent[kind] = now
        return true
    }

    /** التوزيع: ثماني أوراق متتالية بدون خلط (أول التوزيع وباقي الورق) */
    @Suppress("UNUSED_PARAMETER")
    fun deal(newHand: Boolean) = play("deal", gain = 1f, vary = false)

    /** أكل حجر خصم (اللودو والجاكارو): نفس الصوت للعبتين */
    fun capture(at: Double = 0.0) = play("capture", at = at, gain = 1f, vary = false)

    /** نغمة فتح التطبيق (قانون بمقام الراست) */
    fun appOpen() {
        val id = ids["app-open"] ?: return
        if (id in loaded) play("app-open", vary = false) else openPending = true
    }

    /** لاعب انضم للطاولة أو رجع اتصاله (هارب يطلع) / غادرها أو انقطع اتصاله (فقاعتان تنزلان) */
    fun tableJoin() = play("table-join", gain = 0.7f, vary = false)
    fun tableLeave() = play("table-leave", gain = 0.7f, vary = false)

    /** كلمات المزايدة والدبل منطوقة بالترتيب (من الخادم): حكم، صن، بس، ولا، دبل، مقفل... */
    fun voices(keys: List<String>) {
        keys.forEachIndexed { i, k -> play("voice-$k", at = i * 0.7, gain = 1f, vary = false) }
    }

    /** الدومينو: خلط القطع عند التوزيع، وطقة القطعة على الطاولة */
    fun dominoShuffle() = play("domino-shuffle", gain = 1f, vary = false)
    fun dominoTile() = play("domino-tile", gain = 1f)
    /** نهاية الصكة في الدومينو: هارب هادئ */
    fun dominoEnd(at: Double = 0.0) = play("domino-end", at = at, gain = 1f, vary = false)
    /** الجاكارو: صوت وضع الورقة */
    fun jackarooCard() = play("jackaroo-card", gain = 1f)
    /** لودو: رمي النرد */
    fun dice() = play("dice", gain = 0.9f)
    /** مشي الحجر في اللودو: نقرة لكل خطوة */
    // النقرة الوحدة قصيرة جداً (٥٠ جزء من الألف من الثانية): تشغيلها نقرة نقرة كان يضيّع أغلبها في أندرويد
    // (تنسمع نقرة وحدة أو ولا شي). الحين كل عدد خطوات ملف واحد جاهز فيه النقرات كلها بنفس التوقيت
    fun steps(n: Int, at: Double = 0.0) = play("steps-${n.coerceIn(1, 13)}", at = at, gain = 0.9f, vary = false)
    /** مشي حجر الجاكارو: نقرة خفيفة لكل خطوة (غير صوت اللودو) */
    fun marbleSteps(n: Int, at: Double = 0.0) = play("marbles-${n.coerceIn(1, 13)}", at = at, gain = 0.9f, vary = false)

    /** جرس خفيف لك أنت لما تفتح الميكروفون أو تسكّره */
    fun micToggle(open: Boolean) = play(if (open) "mic-on" else "mic-off", gain = 0.8f, vary = false)

    /** أحد انضم للمحادثة الصوتية / غادرها */
    fun voiceJoin() = play("voice-join", gain = 0.7f, vary = false)
    fun voiceLeave() = play("voice-leave", gain = 0.7f, vary = false)

    /** ضغطت ورقة ما يصلح تلعبها */
    fun illegal() = play("illegal", gain = 0.9f, vary = false)
    /** وصلتك دعوة وأنت في التطبيق */
    fun inviteIn() = play("invite-in", gain = 1f, vary = false)
    /** إشعار عام (طلب صداقة، قبول، تنبيه) */
    fun notifyTone() = play("notify", gain = 0.9f, vary = false)
    /** أحد طلب يدخل طاولتك */
    fun joinRequest() = play("join-request", gain = 1f, vary = false)
    /** وصلت رسالة دردشة */
    fun chat() = play("chat-msg", gain = 0.8f, vary = false)
    /** دخل حجر منطقة الأمان (الجاكارو) أو المنزل (اللودو) */
    fun jackarooHome(at: Double = 0.0) = play("jk-home", at = at, gain = 1f, vary = false)
    fun ludoHome(at: Double = 0.0) = play("ludo-home", at = at, gain = 1f, vary = false)
    /** الجاكارو: رجع الحجر ٤ للخلف، أو تبدّل حجرين */
    fun jackarooBack(at: Double = 0.0) = play("jk-back", at = at, gain = 1f, vary = false)
    fun jackarooSwap(at: Double = 0.0) = play("jk-swap", at = at, gain = 1f, vary = false)

    /** أخذ الأكلة: الأوراق تنسحب لصاحبها */
    fun collect() = play("trick-collect", gain = 1f, vary = false)

    fun turn(soft: Boolean) {
        // نغمة الدور (ملف voice-turn)
        play("voice-turn", gain = 1f, vary = false)
    }

    fun handEnd(result: String, kaboot: Boolean) {
        if (kaboot && result != "lose") {
            play("kaboot", gain = 0.8f, vary = false)
            listOf("chips3", "chips4", "chips5", "chips6", "collide2", "collide3").forEachIndexed { i, n -> play(n, at = 0.1 + i * 0.11, gain = 0.85f) }
            return
        }
        // نهاية كل جولة: صوت هادئ (أجراس صغيرة)
        play("hand-end", gain = 0.9f, vary = false)
    }

    fun matchEnd(won: Boolean) = play(if (won) "match-win" else "match-lose", gain = 0.8f, vary = false)

    fun card() = play(pick("card1", "card2", "card3", "card4"), gain = 1f)

    /** القطع بالحكم: ضربة ورقة */
    fun cut() = play("trump-cut", gain = 1f, vary = false) // ورقة ومعها رنة عملة

    /** المشاريع: لكل مشروع صوته (أكبر مشروع في الإعلان)، أصوات ورق وفيش مسجّلة تكبر مع المشروع */
    // كل المشاريع (سرا، خمسين، مية، أربعمية) صوت واحد اختاره صاحب التطبيق.
    // أصوات كل مشروع القديمة باقية في الملفات (proj-sira وproj-fifty وproj-hundred وproj-400) لو نبي نرجع لها
    @Suppress("UNUSED_PARAMETER")
    fun project(kinds: List<String>) = play("proj-reveal", gain = 1f, vary = false)
    /** مشروع البلوت: تسجيلك «بلوت» */
    fun baloot() = play("proj-baloot", gain = 0.8f, vary = false)

    fun hokm() { if (once("hokm")) play("bid", gain = 0.8f, vary = false) }
    /** الصن صوته غير الحكم: نقرة خفيفة */
    fun sun() { if (once("sun")) play("bid-sun", gain = 0.8f, vary = false) }
    fun confirmHokm() { if (once("confirm")) play("bid", gain = 0.7f, vary = false) }

    /** دبل/ثري/فور: الصوت يتكرر بعدد مستواه */
    fun double(level: Int) {
        if (!once("double$level")) return
        repeat(level.coerceAtMost(4)) { play("bid", at = it * 0.2, gain = 0.9f, vary = false) }
    }

    fun gahwa() {
        if (!once("gahwa")) return
        repeat(3) { play("bid", at = it * 0.2, gain = 0.9f, vary = false) }
        play("cup1", at = 0.7, gain = 0.9f)
    }
}
