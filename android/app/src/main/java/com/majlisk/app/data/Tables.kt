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
        kind == "domino" -> "$base ${if (variant == "t150") 150 else if (variant == "t200") 200 else 100}"
        else -> base
    }
}

data class TableRow(
    val id: String, val ownerName: String, val isPrivate: Boolean, val players: Int, val people: Int,
    val status: String, val kind: String, val variant: String,
    /** الموجودين: (الاسم، player|bot|spectator) */
    val members: List<Pair<String, String>> = emptyList(),
    /** نتيجة اللعب الجاري (فاضي إذا ما فيه لعب) */
    val score: String = "",
    /** طاولة ثابتة بكلمة مرور (الباقة الاحترافية) */
    val locked: Boolean = false,
) {
    /** قائمة الموجودين مقروءة: اللاعبين ثم المشاهدين */
    val membersText: String get() {
        if (members.isEmpty()) return "القائمة غير متوفرة الحين"
        val players = members.filter { it.second != "spectator" }.map { if (it.second == "bot") "${it.first} (روبوت)" else it.first }
        val specs = members.filter { it.second == "spectator" }.map { it.first }
        return listOfNotNull(
            if (players.isEmpty()) "ما فيه لاعبين" else "اللاعبين: " + players.joinToString("، "),
            if (specs.isEmpty()) "ما فيه مشاهدين" else "المشاهدين: " + specs.joinToString("، "),
            // اللعب جاري: نتيجة الصكة
            if (status == "playing" && score.isNotEmpty()) score else null,
        ).joinToString("\n")
    }
}

object Tables {
    val ERRORS = mapOf(
        "not-enough-coins" to "رصيدك من العملات لا يكفي",
        "no-username" to "اختر اسم مستخدم أولاً",
        "table-full" to "الطاولة ممتلئة",
        "banned" to "مالك الطاولة حظرك من هذه الطاولة",
        "join-rejected" to "رفض مالك الطاولة طلب انضمامك، تقدر تدخل بدعوة منه أو بعد نصف ساعة من طلبك",
        "banned-by-owner" to "مالك هذه الطاولة حظرك، فلا يمكنك دخول طاولاته",
        "friends-only" to "صاحب الطاولة مفعّل خصوصية اللاعب: طاولته للأصدقاء فقط",
        "kicked" to "أُخرجت من هذه الطاولة، ويمكنك العودة إليها بعد ساعة من طردك، أو قبلها بدعوة من مالكها. يمكنك دخول أي طاولة أخرى الآن",
        "not-found" to "الطاولة غير موجودة",
        "not-a-member" to "لست عضواً في هذه الطاولة",
        "private" to "هذه طاولة خاصة — تحتاج دعوة من مالكها",
        "not-owner" to "هذا الإجراء لمالك الطاولة فقط",
        "wrong-password" to "كلمة المرور غير صحيحة",
        "too-many-attempts" to "محاولات كثيرة غلط، جرّب بعد ربع ساعة",
        "password-required" to "هذه الطاولة بكلمة مرور",
        "bad-password" to "كلمة المرور من 4 إلى 20 حرف",
        "pro-only" to "هذي الميزة للمشتركين في الباقة الاحترافية",
    )

    fun error(e: Throwable, fallback: String) = ERRORS[(e as? ApiError)?.code] ?: fallback

    /** password = طاولة ثابتة بكلمة مرور (الباقة الاحترافية) */
    suspend fun create(isPrivate: Boolean, kind: String, variant: String, password: String? = null): String =
        Api.post("/tables", jsonOf("isPrivate" to isPrivate, "kind" to kind, "variant" to variant, "password" to password)).getString("id")

    suspend fun join(id: String, password: String? = null) { Api.post("/tables/$id/join", jsonOf("password" to password)) }
    /** طلب انضمام لطاولة خاصة (يوصل للمالك تنبيه)، وحالته: pending / accepted / ignored */
    /** الحالة وكم دقيقة باقية (للمعلّق والمرفوض) */
    suspend fun requestJoin(id: String): Pair<String, Int> = Api.post("/tables/$id/join-request").let { it.optString("status") to it.optInt("minutes") }
    suspend fun joinRequestStatus(id: String): Pair<String, Int> = Api.post("/tables/$id/join-request/status").let { it.optString("status") to it.optInt("minutes") }

    suspend fun deleteAccount() { Api.post("/me/delete") }

    private fun rowOf(id: String, g: (String) -> Any?): TableRow = TableRow(
        id = id,
        ownerName = (g("ownerName") as? String).orEmpty(),
        isPrivate = g("isPrivate") == true,
        players = (g("players") as? Number)?.toInt() ?: 0,
        people = (g("people") as? Number)?.toInt() ?: 0,
        status = (g("status") as? String).orEmpty(),
        kind = g("kind") as? String ?: "baloot",
        variant = g("variant") as? String ?: "classic",
        members = runCatching {
            val a = org.json.JSONArray(g("members") as? String ?: "[]")
            (0 until a.length()).map { a.getJSONObject(it).let { o -> o.optString("name") to o.optString("role") } }
        }.getOrDefault(emptyList()),
        score = (g("score") as? String).orEmpty(),
        locked = g("locked") == true,
    )

    /**
     * الطاولات النشطة (أحدث 50) — تتحدث مباشرة. والطاولات الثابتة (برقم سري) مخفية عن القائمة العامة:
     * تطلع بس لصاحبها ولأصدقائه اللي اختارهم (من الخادم، تتحدث كل ٢٠ ثانية)
     */
    fun listen(onRows: (List<TableRow>) -> Unit): ListenerRegistration {
        var fire = emptyList<TableRow>()
        var hidden = emptyList<TableRow>()
        val emit = { onRows(fire.filterNot { it.locked } + hidden) }
        val job = Session.scope.launch {
            while (true) {
                runCatching {
                    val a = Api.post("/tables/visible").optJSONArray("tables") ?: org.json.JSONArray()
                    hidden = (0 until a.length()).map { i -> a.getJSONObject(i).let { o -> rowOf(o.optString("id")) { k -> if (o.has(k)) o.get(k) else null } } }
                    kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.Main) { emit() }
                }
                kotlinx.coroutines.delay(20_000)
            }
        }
        val reg = FirebaseFirestore.getInstance().collection("tables")
            .orderBy("updatedAt", Query.Direction.DESCENDING).limit(50)
            .addSnapshotListener { snap, err ->
                fire = if (err != null || snap == null) emptyList() else snap.documents.map { d -> rowOf(d.id) { k -> d.get(k) } }
                emit()
            }
        return ListenerRegistration { reg.remove(); job.cancel() }
    }
}

/** اتصال حي بالطاولة: يستقبل الحالة والإعلانات، ويعيد الاتصال تلقائياً عند الانقطاع */
/** من نص إعلان الخادم: الانضمام ورجوع الاتصال بنغمة الانضمام، والمغادرة وانقطاع الاتصال بنغمة المغادرة */
private fun eventSound(events: List<String>) {
    when {
        events.any { it.startsWith("انضم ") || it.startsWith("عاد اتصال") } -> Sounds.tableJoin()
        events.any { it.startsWith("غادر ") || it.startsWith("انقطع اتصال") || (it.startsWith("خرج ") && it.contains("من الطاولة")) } -> Sounds.tableLeave()
        events.any { it.endsWith("انضم للمحادثة الصوتية") } -> Sounds.voiceJoin()
        events.any { it.endsWith("غادر المحادثة الصوتية") } -> Sounds.voiceLeave()
    }
}

/** سطور المزايدة والدبل اللي يغطيها التعليق الصوتي */
private val BID_LINE = listOf(
    Regex(".* اشترى .*"), Regex(".* (بس|ولا)$"), Regex(".*أكد الحكم.*"), Regex(".* قال قبلك$"), Regex(".* دبّل$"),
    Regex("^(مقفل|مفتوح)$"), Regex(".*: (مقفل|مفتوح)$"),
)

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
    /** للمالك: صديق يطلب الانضمام لطاولته الخاصة (uid، الاسم) — موافق / تجاهل */
    val joinRequest = MutableStateFlow<Pair<String, String>?>(null)

    // ───── الدردشة الكتابية ─────
    /** مقعدك (لتمييز رسائلك وعدم قراءتها عليك) */
    var myUid: String = ""
    /** نافذة الدردشة مفتوحة الآن (فلا نزيد عدد غير المقروء) */
    var chatOpen = false
        set(v) { field = v; if (v) _unread.value = 0 }
    private val _chat = MutableStateFlow<List<ChatMessage>>(emptyList())
    val chat: StateFlow<List<ChatMessage>> = _chat
    private val _unread = MutableStateFlow(0)
    val unread: StateFlow<Int> = _unread
    /** آخر رسالة وصلت (تظهر لحظات في زاوية الشاشة) */
    private val _toast = MutableStateFlow<ChatMessage?>(null)
    val toast: StateFlow<ChatMessage?> = _toast

    fun sendChat(text: String) {
        val t = text.trim()
        if (t.isNotEmpty()) ws?.send(org.json.JSONObject().put("type", "chat").put("text", t.take(200)).toString())
    }

    private fun sendChatPref() {
        ws?.send(org.json.JSONObject().put("type", "chatPref").put("off", ChatSettings.mode.value == ChatMode.OFF).toString())
    }

    init {
        // تغيّر اختيارك للدردشة: نبلغ الخادم فوراً، وإن أطفأتها نمسح الرسائل
        scope.launch {
            ChatSettings.mode.collect { m ->
                sendChatPref()
                if (m == ChatMode.OFF) { _chat.value = emptyList(); _unread.value = 0; _toast.value = null }
            }
        }
    }

    private var ws: WebSocket? = null
    private var stopped = false
    private var loop: Job? = null
    private var wake = CompletableDeferred<Unit>()

    fun start() {
        // نبقي التطبيق شغال والطاولة مفتوحة حتى لو طلعت منه: بدونها يجمّده Android فتتأخر الأصوات وتعلق
        com.majlisk.app.voice.KeepAlive.table(true)
        loop = scope.launch {
            var retry = 0
            while (!stopped) {
                val token = runCatching { Api.token() }.getOrNull()
                if (token != null) {
                    val done = CompletableDeferred<Unit>()
                    ws = Api.http.newWebSocket(Request.Builder().url(Api.wsUrl("/tables/$tableId/ws", token)).build(), object : WebSocketListener() {
                        override fun onOpen(webSocket: WebSocket, response: Response) {
                            _connected.value = true; retry = 0
                            webSocket.send(org.json.JSONObject().put("type", "chatPref").put("off", ChatSettings.mode.value == ChatMode.OFF).toString())
                            // z: حالة الطاولة توصل مضغوطة (أصغر بثلاث لأربع مرات، أسرع على النت الضعيف)
                            webSocket.send("{\"type\":\"caps\",\"voice\":true,\"z\":true,\"lock\":true}")
                            // حركات انرسلت والاتصال ميت (ضاعت): نعيد إرسالها بالترتيب مع الاتصال الجديد.
                            // كل حركة لها رقم (mid): لو كانت وصلت الخادم قبل، يتجاهلها ويرد بالحالة بس (ما تنحسب مرتين)
                            val now = System.currentTimeMillis()
                            synchronized(outbox) {
                                outbox.removeAll { now - it.at > 20_000 }
                                outbox.forEach { resent = true; webSocket.send(it.text) }
                            }
                        }
                        override fun onMessage(webSocket: WebSocket, text: String) {
                            lastHeard = System.currentTimeMillis()
                            if (text != "pong") { lastData = lastHeard; handle(text) }
                        }
                        override fun onMessage(webSocket: WebSocket, bytes: okio.ByteString) {
                            lastHeard = System.currentTimeMillis(); lastData = lastHeard
                            inflate(bytes.toByteArray())?.let { handle(it) }
                        }
                        override fun onClosed(webSocket: WebSocket, code: Int, reason: String) { done.complete(Unit) }
                        override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) { done.complete(Unit) }
                    })
                    // نبضة كل 3 ثوانٍ: الخادم يكتشف انقطاع نتك خلال ثوانٍ، ونحن نكتشف الاتصال الميت (ما يرد) فنعيده فوراً
                    lastHeard = System.currentTimeMillis(); lastData = lastHeard; syncAt = 0L
                    val beat = scope.launch {
                        while (true) {
                            delay(if (myTurn()) 2_000 else 3_000)
                            val now = System.currentTimeMillis()
                            // ١٢ ثانية بلا أي رد = الاتصال ميت (كانت ٨: على النت الضعيف كانت تقطع وتعيد بلا داعي)
                            // والدور عندك: ٦ ثوانٍ تكفي، فترجع بسرعة وما يحس البقية بتعليق
                            if (now - lastHeard > (if (myTurn()) 6_000 else 12_000)) { ws?.cancel(); break }
                            // طلبنا الحالة وما وصلت خلال ٤ ثوانٍ: الطاولة ما توصلنا (الاتصال معلّق)، نعيده
                            if (syncAt > 0 && lastData < syncAt && now - syncAt > 4_000) { ws?.cancel(); break }
                            // ما وصلنا شي من الطاولة ١٠ ثوانٍ: نطلب الحالة الحالية (لا تبقى الشاشة على حالة قديمة)
                            if (now - lastData > 10_000 && (syncAt == 0L || lastData >= syncAt)) resync()
                            ws?.send("ping")
                        }
                    }
                    done.await()
                    beat.cancel()
                    _connected.value = false
                }
                if (stopped) break
                retry = (retry + 1).coerceAtMost(6)
                // بعد عدة محاولات: هل الطاولة أُغلقت أو أُخرجنا منها؟ أم الشبكة فقط؟
                if (retry >= 3) {
                    val member = runCatching { Api.get("/tables/$tableId/member").optBoolean("member") }.getOrNull()
                    if (member == false) {
                        // غبت أكثر من المهلة (مكالمة مثلاً) فطلعك الخادم من الطاولة: لو الطاولة موجودة نرجعك لها على طول،
                        // وما نقول «أُغلقت الطاولة» إلا لو فعلاً ما تقدر ترجع (انقفلت أو خاصة أو انحذفت)
                        if (runCatching { Tables.join(tableId) }.isSuccess) {
                            Announcer.announce("رجعت للطاولة")
                            retry = 0
                            continue
                        }
                        _closed.value = true; stopped = true; break
                    }
                }
                wake = CompletableDeferred()
                // يرجع النت: نعيد الاتصال على طول بدل انتظار المحاولة التالية
                // أول محاولة على طول، وبعدها تتباعد شوي (ثانية، ثنتين، ...)
                kotlinx.coroutines.withTimeoutOrNull(1000L * (retry - 1)) { wake.await() }
            }
        }
    }

    /** العودة للتطبيق: نعيد الاتصال فوراً بدل انتظار المحاولة التالية */
    fun reconnectNow() { if (!_connected.value) wake.complete(Unit) else resync() }

    /** نطلب الحالة الحالية من الطاولة (ونتأكد إن الاتصال يوصل لها فعلاً) */
    fun resync() {
        if (!_connected.value) return
        syncAt = System.currentTimeMillis()
        ws?.send("{\"type\":\"sync\"}")
    }

    /** الدور عندك الحين (في أي لعبة) */
    private fun myTurn(): Boolean = _view.value?.let { v ->
        v.game?.myTurn == true || v.domino?.myTurn == true || v.jackaroo?.myTurn == true || v.ludo?.myTurn == true
    } ?: false

    @Volatile private var lastHeard = 0L
    /** آخر رسالة حقيقية من الطاولة (غير رد النبضة) */
    @Volatile private var lastData = 0L
    /** متى طلبنا الحالة (0 = ما فيه طلب ينتظر) */
    @Volatile private var syncAt = 0L
    // رجع النت (أو تغيّرت الشبكة): نعيد الاتصال فوراً، فيُعلن رجوعك للبقية على طول
    private val connectivity = com.majlisk.app.MajliskApp.instance.getSystemService(android.net.ConnectivityManager::class.java)
    private val netCallback = object : android.net.ConnectivityManager.NetworkCallback() {
        override fun onAvailable(network: android.net.Network) {
            scope.launch {
                // تغيّرت الشبكة والدور عندك: الاتصال القديم غالباً مات، نعيده على طول بدل ما ننتظر نكتشف
                if (_connected.value && (myTurn() || System.currentTimeMillis() - lastHeard > 3_500)) ws?.cancel()
                reconnectNow()
            }
        }
    }
    init { runCatching { connectivity.registerDefaultNetworkCallback(netCallback) } }

    private fun handle(text: String) {
        val msg = runCatching { JSONObject(text) }.getOrNull() ?: return
        when (msg.optString("type")) {
            // المحادثة الصوتية من غرفتها المستقلة: نحدّث القائمة بس (بدون الطاولة كاملة)
            "voice" -> {
                val list = com.majlisk.app.model.parseVoice(msg.optJSONArray("voice"))
                serverView = serverView?.copy(voice = list)
                _view.value?.let { v -> val next = v.copy(voice = list); _view.value = next; onState?.invoke(next) }
                scope.launch { com.majlisk.app.voice.Voice.sync(list, tableId) }
            }
            "state" -> runCatching { TableView.parse(msg.getJSONObject("view")) }.onSuccess { server ->
                // خادم قديم (ما يرد بـ ack): أي حالة تعتبر رد على الحركات
                if (!serverAcks) synchronized(outbox) { outbox.clear() }
                serverView = server
                // حركتك الفورية لسا ما وصلت الخادم: تبقى ظاهرة على الحالة الجديدة (ما ترجع الورقة ليدك وتطلع ثاني)
                val shown = optimistic?.let { f -> f(server) ?: run { optimistic = null; null } } ?: server
                _view.value = shown; onState?.invoke(shown); scope.launch { com.majlisk.app.voice.Voice.sync(server.voice, tableId) }
            }
            // الخادم استلم الحركة ونفّذها (أو كانت منفّذة قبل)
            "ack" -> {
                serverAcks = true
                val mid = msg.optString("mid")
                synchronized(outbox) { outbox.removeAll { it.mid == mid } }
                // وصل التأكيد والحركة الفورية لسا معروضة = الخادم تجاهلها (مثلاً وقت مهلة الأكلة): نرجع لحالته
                if (optimisticMid == mid && optimistic != null) {
                    optimistic = null; optimisticMid = null
                    Sounds.clearLocal()
                    serverView?.let { _view.value = it; onState?.invoke(it) }
                }
            }
            // كل حدث إعلان مستقل حتى يقرأها قارئ الشاشة بالترتيب
            // أحداث الحركة الواحدة تُقرأ جملة واحدة، وتنتظر ما قبلها حتى يكتمل (لا تقطع بعضها)
            "events" -> msg.optJSONArray("events")?.let { a ->
                val events = (0 until a.length()).map { a.optString(it) }
                // المزايدة والدبل بأصوات منطوقة (حكم، صن، بس/ولا، دبل...)
                val voices = msg.optJSONArray("voices")?.let { v -> (0 until v.length()).map { v.optString(it) } }.orEmpty()
                if (voices.isNotEmpty()) Sounds.voices(voices)
                eventSound(events)
                // المزايدة والدبل: التعليق الصوتي يبيّن وش اشترى أو قال، فقارئ الشاشة ما يقرأ نصها
                // (يقول بس «دور فلان» مع تغيّر الدور)، ويبقى ما سواها مثل «ورقة الأرض لفلان»
                val spoken = if (voices.isEmpty()) events else events.filterNot { e -> BID_LINE.any { it.matches(e) } }
                if (spoken.isNotEmpty()) Announcer.announceEvent(spoken.joinToString("، "), urgent = _view.value?.ludo != null)
            }
            "joinRequest" -> scope.launch {
                val name = msg.optString("name")
                joinRequest.value = msg.optString("uid") to name
                Sounds.joinRequest()
                // قارئ الشاشة يقرأ الطلب على طول
                Announcer.announceNow("$name طلب الانضمام")
            }
            "chat" -> {
                val mode = ChatSettings.mode.value
                if (mode == ChatMode.OFF) return
                val m = ChatMessage(msg.optString("uid"), msg.optString("name"), msg.optString("text"), msg.optString("uid") == myUid)
                _chat.value = (_chat.value + m).takeLast(100)
                // سطر من الطاولة نفسها (مثل الدعوات): ينكتب في الدردشة بس، لأن قارئ الشاشة قرأه من الإعلان
                if (m.uid == "system") return
                // صوت الدردشة حتى للمرسل: رجعت رسالتك من الخادم = انرسلت فعلاً
                Sounds.chat()
                if (!m.mine) {
                    if (!chatOpen) _unread.value += 1
                    _toast.value = m
                    if (mode == ChatMode.READ) Announcer.announce("${m.name}: ${m.text}")
                }
            }
            "error" -> {
                val mid = msg.optString("mid").takeIf { it.isNotEmpty() }
                synchronized(outbox) { if (mid != null) outbox.removeAll { it.mid == mid } else if (!serverAcks) outbox.clear() }
                // الحركة الفورية رُفضت: ترجع الورقة ليدك
                if (optimistic != null && (mid == null || mid == optimisticMid)) {
                    optimistic = null; optimisticMid = null
                    Sounds.clearLocal()
                    serverView?.let { _view.value = it; onState?.invoke(it) }
                }
                if (resent) resent = false else Announcer.announce(msg.optString("message"))
            }
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

    /**
     * آخر حركة لعب انرسلت ولسا ما جا رد الخادم عليها. لو الاتصال ميت وهو يبان شغال (النت انقطع ثواني)
     * كانت الحركة تضيع: الحين لو ما وصل شي من الخادم خلال ثانيتين ونص نعيد الاتصال على طول،
     * ونعيد إرسال الحركة مع الاتصال الجديد
     */
    private data class Outgoing(val mid: String, val text: String, val at: Long)
    /** الحركات اللي انرسلت ولسا ما أكدها الخادم (ack): تنعاد بالترتيب لو انقطع الاتصال */
    private val outbox = ArrayList<Outgoing>()
    /** الخادم الجديد يرد بـ ack على كل حركة (القديم ما يرد) */
    @Volatile private var serverAcks = false
    /** أعدنا إرسال حركة: لو كانت انلعبت قبل، خطأ الخادم («ليس دورك») ما ينقرأ */
    @Volatile private var resent = false
    /** آخر حالة من الخادم (بدون اللعب الفوري): نرجع لها لو رُفضت الحركة */
    @Volatile private var serverView: TableView? = null
    /** اللعب الفوري: الحركة اللي تنعرض قبل رد الخادم، ورقمها */
    @Volatile private var optimistic: ((TableView) -> TableView?)? = null
    @Volatile private var optimisticMid: String? = null
    private var seq = 0
    private val watchdog = android.os.Handler(android.os.Looper.getMainLooper())

    fun send(msg: JSONObject) {
        val isMove = msg.has("action")
        val at = System.currentTimeMillis()
        if (isMove) {
            val mid = "${at.toString(36)}-${++seq}"
            msg.put("mid", mid)
            val text = msg.toString()
            synchronized(outbox) { outbox.add(Outgoing(mid, text, at)) }
            resent = false
            // اللعب الفوري: الورقة تطلع من يدك على طول، والخادم يأكدها بعدين
            // على المعروض الحين (فضغطتين ورا بعض على نفس الورقة ما تنلعب مرتين)
            _view.value?.let { base ->
                Optimistic.patch(base, msg)?.let { f -> f(base)?.let { shown ->
                    optimistic = f; optimisticMid = mid
                    _view.value = shown; onState?.invoke(shown)
                } }
            }
            val ok = ws?.takeIf { _connected.value }?.send(text) ?: false
            // ما فيه اتصال الحين: الحركة محفوظة وتنرسل أول ما يرجع
            if (!ok) { Announcer.announce("جارٍ إعادة الاتصال بالطاولة…"); return }
            // ما وصل أي شي من الخادم خلال ٥ ثوانٍ: الاتصال ميت، نعيده (والحركة تنعاد معه)
            watchdog.postDelayed({
                val waiting = synchronized(outbox) { outbox.any { it.mid == mid } }
                if (waiting && lastHeard < at) ws?.cancel()
            }, 5_000)
            return
        }
        val ok = ws?.takeIf { _connected.value }?.send(msg.toString()) ?: false
        if (!ok) Announcer.announce("جارٍ إعادة الاتصال بالطاولة…")
    }

    /** حالة مضغوطة من الخادم (deflate-raw) */
    private fun inflate(data: ByteArray): String? = runCatching {
        val inf = java.util.zip.Inflater(true)
        inf.setInput(data)
        val out = java.io.ByteArrayOutputStream(data.size * 4)
        val buf = ByteArray(8192)
        while (!inf.finished()) {
            val n = inf.inflate(buf)
            if (n == 0 && (inf.needsInput() || inf.needsDictionary())) break
            out.write(buf, 0, n)
        }
        inf.end()
        out.toString("UTF-8")
    }.getOrNull()

    fun send(type: String, vararg pairs: Pair<String, Any?>) = send(jsonOf("type" to type, *pairs))

    fun stop() {
        stopped = true
        com.majlisk.app.voice.KeepAlive.table(false)
        runCatching { connectivity.unregisterNetworkCallback(netCallback) }
        ws?.close(1000, null)
        scope.cancel()
    }
}
