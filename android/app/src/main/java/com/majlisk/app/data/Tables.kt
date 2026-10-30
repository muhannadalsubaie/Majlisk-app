package com.majlisk.app.data

import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.ListenerRegistration
import com.google.firebase.firestore.Query
import com.majlisk.app.a11y.Announcer
import com.majlisk.app.model.TableView
import com.majlisk.app.net.Api
import com.majlisk.app.net.ApiError
import com.majlisk.app.net.jsonOf
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import org.json.JSONObject

val GAME_NAMES = mapOf("baloot" to "بلوت", "domino" to "دومينو", "jackaroo" to "جاكارو", "ludo" to "لودو")

/** اسم اللعبة كما في الخادم (shared/games.ts → gameTitle) */
fun gameTitle(kind: String, variant: String?): String {
    val base = GAME_NAMES[kind] ?: "بلوت"
    return when {
        kind == "jackaroo" && variant == "complex" -> "$base كمبلكس"
        kind == "ludo" && variant == "teams" -> "$base فرق"
        else -> base
    }
}

data class TableRow(
    val id: String, val ownerName: String, val isPrivate: Boolean, val players: Int, val people: Int,
    val status: String, val kind: String, val variant: String,
)

object Tables {
    val ERRORS = mapOf(
        "not-enough-coins" to "رصيدك من العملات لا يكفي",
        "no-username" to "اختر اسم مستخدم أولاً",
        "table-full" to "الطاولة ممتلئة",
        "banned" to "مالك الطاولة حظرك من هذه الطاولة",
        "banned-by-owner" to "مالك هذه الطاولة حظرك، فلا يمكنك دخول طاولاته",
        "kicked" to "أُخرجت من هذه الطاولة، ويمكنك العودة إليها بعد ساعة من طردك. يمكنك دخول أي طاولة أخرى الآن",
        "not-found" to "الطاولة غير موجودة",
        "not-a-member" to "لست عضواً في هذه الطاولة",
        "private" to "هذه طاولة خاصة — تحتاج دعوة من مالكها",
        "not-owner" to "هذا الإجراء لمالك الطاولة فقط",
    )

    fun error(e: Throwable, fallback: String) = ERRORS[(e as? ApiError)?.code] ?: fallback

    suspend fun create(isPrivate: Boolean, kind: String, variant: String): String =
        Api.post("/tables", jsonOf("isPrivate" to isPrivate, "kind" to kind, "variant" to variant)).getString("id")

    suspend fun join(id: String) { Api.post("/tables/$id/join") }

    suspend fun deleteAccount() { Api.post("/me/delete") }

    /** الطاولات النشطة (أحدث 50) — تتحدث مباشرة */
    fun listen(onRows: (List<TableRow>) -> Unit): ListenerRegistration =
        FirebaseFirestore.getInstance().collection("tables")
            .orderBy("updatedAt", Query.Direction.DESCENDING).limit(50)
            .addSnapshotListener { snap, err ->
                if (err != null || snap == null) { onRows(emptyList()); return@addSnapshotListener }
                onRows(snap.documents.map { d ->
                    TableRow(
                        id = d.id,
                        ownerName = d.getString("ownerName").orEmpty(),
                        isPrivate = d.getBoolean("isPrivate") == true,
                        players = (d.getLong("players") ?: 0).toInt(),
                        people = (d.getLong("people") ?: 0).toInt(),
                        status = d.getString("status").orEmpty(),
                        kind = d.getString("kind") ?: "baloot",
                        variant = d.getString("variant") ?: "classic",
                    )
                })
            }
}

/** اتصال حي بالطاولة: يستقبل الحالة والإعلانات، ويعيد الاتصال تلقائياً عند الانقطاع */
/** من نص إعلان الخادم: الانضمام ورجوع الاتصال بنغمة الانضمام، والمغادرة وانقطاع الاتصال بنغمة المغادرة */
private fun eventSound(events: List<String>) {
    when {
        events.any { it.startsWith("انضم ") || it.startsWith("عاد اتصال") } -> Sounds.tableJoin()
        events.any { it.startsWith("غادر ") || it.startsWith("انقطع اتصال") || (it.startsWith("خرج ") && it.contains("من الطاولة")) } -> Sounds.tableLeave()
    }
}

class TableConnection(val tableId: String) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private val _view = MutableStateFlow<TableView?>(null)
    /** يُستدعى مع كل حالة تصل (حتى والتطبيق في الخلفية): لأصوات اللعب */
    var onState: ((TableView) -> Unit)? = null
    val view: StateFlow<TableView?> = _view
    private val _connected = MutableStateFlow(false)
    val connected: StateFlow<Boolean> = _connected
    private val _closed = MutableStateFlow(false)
    val closed: StateFlow<Boolean> = _closed
    /** أخرجه المالك أو حظره: لا نعيد الاتصال */
    private val _kicked = MutableStateFlow<String?>(null)
    val kicked: StateFlow<String?> = _kicked

    private var ws: WebSocket? = null
    private var stopped = false
    private var loop: Job? = null
    private var wake = CompletableDeferred<Unit>()

    fun start() {
        loop = scope.launch {
            var retry = 0
            while (!stopped) {
                val token = runCatching { Api.token() }.getOrNull()
                if (token != null) {
                    val done = CompletableDeferred<Unit>()
                    ws = Api.http.newWebSocket(Request.Builder().url(Api.wsUrl("/tables/$tableId/ws", token)).build(), object : WebSocketListener() {
                        override fun onOpen(webSocket: WebSocket, response: Response) { _connected.value = true; retry = 0 }
                        override fun onMessage(webSocket: WebSocket, text: String) { handle(text) }
                        override fun onClosed(webSocket: WebSocket, code: Int, reason: String) { done.complete(Unit) }
                        override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) { done.complete(Unit) }
                    })
                    // نبضة كل 10 ثوانٍ: إذا انقطع نتك بلا إغلاق للاتصال يعرف الخادم خلال ثوانٍ ويعلن انقطاعك
                    val beat = scope.launch { while (true) { delay(10_000); ws?.send("ping") } }
                    done.await()
                    beat.cancel()
                    _connected.value = false
                }
                if (stopped) break
                retry = (retry + 1).coerceAtMost(6)
                // بعد عدة محاولات: هل الطاولة أُغلقت أو أُخرجنا منها؟ أم الشبكة فقط؟
                if (retry >= 3) {
                    val member = runCatching { Api.get("/tables/$tableId/member").optBoolean("member") }.getOrNull()
                    if (member == false) { _closed.value = true; stopped = true; break }
                }
                wake = CompletableDeferred()
                kotlinx.coroutines.withTimeoutOrNull(1000L * retry) { wake.await() }
            }
        }
    }

    /** العودة للتطبيق: نعيد الاتصال فوراً بدل انتظار المحاولة التالية */
    fun reconnectNow() { if (!_connected.value) wake.complete(Unit) }

    private fun handle(text: String) {
        val msg = runCatching { JSONObject(text) }.getOrNull() ?: return
        when (msg.optString("type")) {
            "state" -> runCatching { TableView.parse(msg.getJSONObject("view")) }.onSuccess { _view.value = it; onState?.invoke(it) }
            // كل حدث إعلان مستقل حتى يقرأها قارئ الشاشة بالترتيب
            // أحداث الحركة الواحدة تُقرأ جملة واحدة، وتنتظر ما قبلها حتى يكتمل (لا تقطع بعضها)
            "events" -> msg.optJSONArray("events")?.let { a ->
                val events = (0 until a.length()).map { a.optString(it) }
                eventSound(events)
                Announcer.announceEvent(events.joinToString("، "))
            }
            "error" -> Announcer.announce(msg.optString("message"))
            "kicked" -> {
                stopped = true
                val banned = msg.optBoolean("banned")
                _kicked.value = if (banned) "banned" else "kicked"
                Announcer.announce(if (banned) "حظرك مالك الطاولة" else "أخرجك مالك الطاولة")
            }
            "closed" -> {
                stopped = true
                _closed.value = true
                Announcer.announce("أُغلقت الطاولة")
            }
        }
    }

    fun send(msg: JSONObject) {
        val ok = ws?.takeIf { _connected.value }?.send(msg.toString()) ?: false
        if (!ok) Announcer.announce("جارٍ إعادة الاتصال بالطاولة…")
    }

    fun send(type: String, vararg pairs: Pair<String, Any?>) = send(jsonOf("type" to type, *pairs))

    fun stop() {
        stopped = true
        ws?.close(1000, null)
        scope.cancel()
    }
}
