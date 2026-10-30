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
    private lateinit var pool: SoundPool
    private val ids = HashMap<String, Int>()
    private val main = Handler(Looper.getMainLooper())
    private val recent = HashMap<String, Long>()

    private val FILES = listOf(
        "card1", "card2", "card3", "card4", "slide1", "slide2", "slide3", "slide4",
        "shove1", "shove2", "shove3", "shove4", "shuffle", "fan", "chips1", "chips2", "collide",
        "knock1", "cup1", "slide7", "chips3", "chips4", "chips5", "chips6",
        "collide2", "collide3", "collide4", "lay1", "lay2", "handle1", "turn", "match-win", "match-lose", "kaboot", "bid",
        "app-open", "table-join", "table-leave", "proj-sira", "proj-fifty", "bid-sun", "proj-hundred", "proj-400",
    )
    private val loaded = HashSet<Int>()
    private var openPending = false

    fun init(c: Context) {
        pool = SoundPool.Builder().setMaxStreams(8).setAudioAttributes(
            AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_GAME).setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build(),
        ).build()
        // نغمة الفتح قد تُطلب قبل اكتمال تحميلها: تُشغَّل لحظة جاهزيتها
        pool.setOnLoadCompleteListener { p, id, status ->
            if (status != 0) return@setOnLoadCompleteListener
            loaded += id
            if (openPending && id == ids["app-open"]) { openPending = false; if (!Prefs.muted) p.play(id, 0.8f, 0.8f, 1, 0, 1f) }
        }
        for (name in FILES) {
            runCatching { c.assets.openFd("sounds/$name.mp3").use { ids[name] = pool.load(it, 1) } }
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
    fun deal(newHand: Boolean) {
        listOf("slide1", "slide2", "slide3", "slide4", "slide1", "slide2", "slide3", "slide4")
            .forEachIndexed { i, n -> play(n, at = i * 0.1, gain = 0.6f) }
    }

    /** نغمة فتح التطبيق (قانون بمقام الراست) */
    fun appOpen() {
        val id = ids["app-open"] ?: return
        if (id in loaded) play("app-open", vary = false) else openPending = true
    }

    /** لاعب انضم للطاولة أو رجع اتصاله (هارب يطلع) / غادرها أو انقطع اتصاله (فقاعتان تنزلان) */
    fun tableJoin() = play("table-join", gain = 0.7f, vary = false)
    fun tableLeave() = play("table-leave", gain = 0.7f, vary = false)

    fun collect() = play("slide7", gain = 0.8f, vary = false)

    fun turn(soft: Boolean) {
        if (!Prefs.turnChime) return
        // بصوت واضح حتى مع قارئ الشاشة (كان خافتاً معه فما ينسمع)
        play("turn", gain = 0.6f, vary = false)
    }

    fun handEnd(result: String, kaboot: Boolean) {
        if (kaboot && result != "lose") {
            play("kaboot", gain = 0.8f, vary = false)
            listOf("chips3", "chips4", "chips5", "chips6", "collide2", "collide3").forEachIndexed { i, n -> play(n, at = 0.1 + i * 0.11, gain = 0.85f) }
            return
        }
        when (result) {
            "win" -> { play("chips3", gain = 0.85f); play("chips4", at = 0.14, gain = 0.8f); play("collide2", at = 0.32, gain = 0.75f); play("handle1", at = 0.5, gain = 0.6f) }
            "lose" -> { play("lay1", gain = 0.7f); play("lay2", at = 0.22, gain = 0.5f) }
            else -> { play("chips3", gain = 0.6f); play("collide2", at = 0.2, gain = 0.5f) }
        }
    }

    fun matchEnd(won: Boolean) = play(if (won) "match-win" else "match-lose", gain = 0.8f, vary = false)

    fun card() = play(pick("card1", "card2", "card3", "card4"))

    /** القطع بالحكم: ضربة ورقة */
    fun cut() {
        play("collide4", gain = 1f)
        play("slide7", at = 0.02, gain = 0.8f)
    }

    /** المشاريع: لكل مشروع صوته (أكبر مشروع في الإعلان)، أصوات ورق وفيش مسجّلة تكبر مع المشروع */
    fun project(kinds: List<String>) = when {
        kinds.contains("أربعمية") -> play("proj-400", gain = 0.8f, vary = false)
        kinds.any { it == "مية" || it == "مية وخمسين" } -> play("proj-hundred", gain = 0.8f, vary = false)
        kinds.contains("خمسين") -> play("proj-fifty", gain = 0.8f, vary = false)
        else -> play("proj-sira", gain = 0.8f, vary = false)
    }
    fun baloot() { play("collide", gain = 0.7f); play("chips2", at = 0.15, gain = 0.7f) }

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
