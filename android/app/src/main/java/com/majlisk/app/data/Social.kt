package com.majlisk.app.data

import com.majlisk.app.a11y.Announcer
import com.majlisk.app.model.objects
import com.majlisk.app.net.Api
import com.majlisk.app.net.ApiError
import com.majlisk.app.net.jsonOf
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import org.json.JSONObject

/** tableId: الطاولة اللي فيها الصديق المتصل الآن (إن وُجدت) */
data class Friend(val uid: String, val username: String, val online: Boolean = false, val tableId: String? = null, val tablePrivate: Boolean = false, val tableGame: String = "")
data class TableInvite(val tableId: String, val code: String, val fromUid: String, val fromName: String)
data class HubState(val friends: List<Friend> = emptyList(), val requests: List<Friend> = emptyList(), val invites: List<TableInvite> = emptyList())

private fun friends(o: JSONObject, key: String) = o.optJSONArray(key).objects().map { Friend(it.optString("uid"), it.optString("username"), it.optBoolean("online"), it.optString("tableId").ifEmpty { null }, it.optBoolean("tablePrivate"),
    if (it.has("tableKind")) gameTitle(it.optString("tableKind"), it.optString("tableVariant")) else "") }
private fun invites(o: JSONObject) = o.optJSONArray("invites").objects().map {
    TableInvite(it.optString("tableId"), it.optString("code"), it.optString("fromUid"), it.optString("fromName"))
}

object Social {
    suspend fun listFriends(): HubState = Api.post("/friends/list").let { HubState(friends(it, "friends"), friends(it, "requests"), invites(it)) }
    /** true = أصبحتما صديقين مباشرة (كان قد أرسل لك طلباً) */
    suspend fun requestFriend(username: String): Boolean = Api.post("/friends/request", jsonOf("username" to username)).optBoolean("friends")
    suspend fun respondFriend(uid: String, accept: Boolean) { Api.post("/friends/respond", jsonOf("uid" to uid, "accept" to accept)) }
    suspend fun removeFriend(uid: String) { Api.post("/friends/remove", jsonOf("uid" to uid)) }
    suspend fun listBans(): List<Friend> = friends(Api.post("/bans/list"), "bans")
    suspend fun unban(uid: String) { Api.post("/bans/remove", jsonOf("uid" to uid)) }
    suspend fun inviteFriend(tableId: String, uid: String, seat: Int? = null) {
        Api.post("/tables/$tableId/inviteFriend", jsonOf("uid" to uid, "seat" to seat))
    }
    /** يرجع معرّف الطاولة عند القبول */
    suspend fun respondInvite(tableId: String, accept: Boolean) { Api.post("/invites/respond", jsonOf("tableId" to tableId, "accept" to accept)) }

    private val ERRORS = mapOf(
        "user-not-found" to "لا يوجد لاعب بهذا الاسم",
        "self" to "هذا اسمك أنت",
        "already-friends" to "أنتما صديقان بالفعل",
        "not-friends" to "هذا اللاعب ليس في قائمة أصدقائك",
        "offline" to "صديقك غير متصل الآن",
        "no-invite" to "انتهت صلاحية الدعوة",
        "not-enough-coins" to "رصيدك من العملات لا يكفي",
        "not-owner" to "الدعوة لمالك الطاولة فقط",
        "table-full" to "الطاولة ممتلئة",
        "not-found" to "الطاولة لم تعد موجودة",
        "no-username" to "اختر اسم مستخدم أولاً",
    )

    fun error(e: Throwable): String = ERRORS[(e as? ApiError)?.code] ?: "حدث خطأ، حاول مرة أخرى"
}

/**
 * اتصال دائم بمركز اللاعب أثناء تشغيل التطبيق: يجعلك "متصلاً" لأصدقائك،
 * ويستقبل طلبات الصداقة والدعوات فوراً.
 */
object Hub {
    private val _state = MutableStateFlow(HubState())
    val state: StateFlow<HubState> = _state
    /** يزيد كلما اتصل صديق أو خرج: قائمة الأصدقاء تتحدث فوراً */
    private val _presence = MutableStateFlow(0)
    val presence: StateFlow<Int> = _presence
    private var ws: WebSocket? = null
    private var job: Job? = null
    private var enabled = false

    fun start() {
        if (enabled) return
        enabled = true
        job = Session.scope.launch {
            var retry = 0
            while (enabled) {
                val token = runCatching { Api.token() }.getOrNull()
                if (token == null) { delay(3000); continue }
                val closed = kotlinx.coroutines.CompletableDeferred<Unit>()
                ws = Api.http.newWebSocket(Request.Builder().url(Api.wsUrl("/me/ws", token)).build(), object : WebSocketListener() {
                    override fun onOpen(webSocket: WebSocket, response: Response) { retry = 0 }
                    override fun onMessage(webSocket: WebSocket, text: String) {
                        if (text == "pong") return
                        val msg = runCatching { JSONObject(text) }.getOrNull() ?: return
                        when (msg.optString("type")) {
                            "state" -> _state.value = HubState(friends(msg, "friends"), friends(msg, "requests"), invites(msg))
                            "presence" -> _presence.value++
                            "notice" -> Announcer.announce(msg.optString("text"))
                            "invite" -> Announcer.announce("${msg.optJSONObject("invite")?.optString("fromName")} يدعوك لطاولته")
                        }
                    }
                    override fun onClosed(webSocket: WebSocket, code: Int, reason: String) { closed.complete(Unit) }
                    override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) { closed.complete(Unit) }
                })
                // نبضة كل 15 ثانية: بها يعرف الخادم أنك متصل (وإذا انقطعت تصير "غير متصل" لأصدقائك)
                val ping = launch { while (true) { delay(15_000); ws?.send("ping") } }
                closed.await()
                ping.cancel()
                if (!enabled) break
                retry = (retry + 1).coerceAtMost(6)
                delay(1500L * retry)
            }
        }
    }

    fun stop() {
        enabled = false
        job?.cancel()
        ws?.close(1000, null)
        ws = null
        _state.value = HubState()
    }

    /** أزل دعوة من القائمة محلياً بعد الرد عليها */
    fun dropInvite(tableId: String) {
        _state.value = _state.value.copy(invites = _state.value.invites.filter { it.tableId != tableId })
    }
}
