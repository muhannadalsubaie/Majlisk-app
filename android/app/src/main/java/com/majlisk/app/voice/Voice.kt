package com.majlisk.app.voice

import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioDeviceInfo
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.os.Build
import androidx.core.content.ContextCompat
import com.majlisk.app.MainActivity
import com.majlisk.app.MajliskApp
import com.majlisk.app.a11y.Announcer
import com.majlisk.app.data.Session
import com.majlisk.app.model.VoiceMember
import com.majlisk.app.model.objects
import com.majlisk.app.net.Api
import com.majlisk.app.net.ApiError
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import org.json.JSONObject
import org.webrtc.AudioTrack
import org.webrtc.MediaConstraints
import org.webrtc.MediaStream
import org.webrtc.PeerConnection
import org.webrtc.PeerConnectionFactory
import org.webrtc.RtpReceiver
import org.webrtc.RtpTransceiver
import org.webrtc.SdpObserver
import org.webrtc.SessionDescription
import org.webrtc.audio.JavaAudioDeviceModule
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

/**
 * المحادثة الصوتية للطاولة عبر Cloudflare Realtime (WebRTC) — نفس طريقة التطبيق الحالي:
 * كل شخص ينشر ميكروفونه في جلسة خاصة به، ويسحب أصوات بقية المنضمين إلى نفس الاتصال.
 * الخادم (غرفة الطاولة) يمرر الطلبات ويتحقق أن الشخص في الطاولة ويملك جلسته.
 * يبدأ الميكروفون مكتوماً دائماً (استماع فقط)، والكتم محلي دون إعادة تفاوض.
 */
object Voice {
    enum class Mode { Manual, Auto, Rejoin }
    /** reconnecting: إعادة اتصال صامتة بعد انقطاع — الزر يبقى على حاله (لا يظهر "خارج المحادثة") */
    data class State(val joined: Boolean = false, val muted: Boolean = true, val busy: Boolean = false, val reconnecting: Boolean = false)

    private val _state = MutableStateFlow(State())
    val state: StateFlow<State> = _state
    private fun set(f: State.() -> State) { _state.value = _state.value.f() }

    private val ctx: Context get() = MajliskApp.instance
    private val lock = Mutex()
    private var tableId: String? = null
    private var myUid = ""
    private var pc: PeerConnection? = null
    private var mic: AudioTrack? = null
    private var micSource: org.webrtc.AudioSource? = null
    private var sessionId: String? = null
    /** من أسحب صوته: uid:session → mid */
    private val pulled = HashMap<String, String>()
    private var members: List<VoiceMember> = emptyList()
    private var leaving = false
    private var rejoining = false
    private var autoRetries = 0
    private var missingJob: Job? = null

    private val factory: PeerConnectionFactory by lazy {
        PeerConnectionFactory.initialize(PeerConnectionFactory.InitializationOptions.builder(ctx).createInitializationOptions())
        val adm = JavaAudioDeviceModule.builder(ctx)
            .setUseHardwareAcousticEchoCanceler(true)
            .setUseHardwareNoiseSuppressor(true)
            .createAudioDeviceModule()
        PeerConnectionFactory.builder().setAudioDeviceModule(adm).createPeerConnectionFactory()
    }

    private suspend fun request(body: JSONObject): JSONObject = Api.post("/tables/$tableId/voice", body)
    private fun desc(d: SessionDescription) = JSONObject().put("type", d.type.canonicalForm()).put("sdp", d.description)
    private fun parseDesc(o: JSONObject?) = o?.let { SessionDescription(SessionDescription.Type.fromCanonicalForm(it.optString("type")), it.optString("sdp")) }

    /** الانضمام: جلسة استماع فقط بلا ميكروفون — لا يُطلب إذن الميكروفون حتى تفتحه بنفسك */
    fun join(id: String, uid: String, mode: Mode = Mode.Manual) {
        Session.scope.launch {
            lock.withLock {
                if (_state.value.joined || _state.value.busy) return@launch
                set { copy(busy = true) }
                tableId = id
                myUid = uid
                try {
                    val config = PeerConnection.RTCConfiguration(listOf(PeerConnection.IceServer.builder("stun:stun.cloudflare.com:3478").createIceServer())).apply {
                        bundlePolicy = PeerConnection.BundlePolicy.MAXBUNDLE
                        sdpSemantics = PeerConnection.SdpSemantics.UNIFIED_PLAN
                    }
                    lateinit var created: PeerConnection
                    created = factory.createPeerConnection(config, object : PeerObserver() {
                        override fun onConnectionChange(newState: PeerConnection.PeerConnectionState) {
                            // انقطع اتصال الصوت نفسه (تغيّر الشبكة، مكالمة): نعيد الانضمام مكتومين
                            if (newState == PeerConnection.PeerConnectionState.FAILED && pc === created && _state.value.joined && !leaving) rejoin()
                        }
                    }) ?: throw ApiError("voice-failed")
                    pc = created
                    val r = request(JSONObject().put("op", "session"))
                    sessionId = r.getString("sessionId")
                    members = members.filter { it.uid != uid } + VoiceMember(uid, "", sessionId!!, muted = true, mic = false, blocked = false)
                    set { State(joined = true, muted = true, busy = false) }
                    audio(true)
                    autoRetries = 0
                    if (mode != Mode.Rejoin) Announcer.announce("أنت في المحادثة الصوتية، والميكروفون مغلق")
                } catch (e: Exception) {
                    cleanup()
                    val code = (e as? ApiError)?.code
                    // الانضمام التلقائي يفشل بصمت، ويعيد المحاولة بعد قليل إن كان الخطأ عابراً
                    val retry = mode != Mode.Manual && code != "voice-not-configured" && code != "voice-limit" && autoRetries < 3
                    if (!retry) set { copy(reconnecting = false) }
                    if (retry) {
                        autoRetries++
                        val wait = 5000L * autoRetries
                        Session.scope.launch { delay(wait); if (!_state.value.joined && tableId == id) join(id, uid, mode) }
                    }
                    if (mode == Mode.Manual) Announcer.announce(when (code) {
                        "voice-not-configured" -> "المحادثة الصوتية غير مفعّلة بعد"
                        "voice-limit" -> "المحادثة الصوتية وصلت لحدها هذا الشهر، وترجع بداية الشهر الجاي"
                        else -> "تعذّر الانضمام للمحادثة الصوتية، حاول مرة أخرى"
                    })
                    return@launch
                }
            }
            sync(members)
        }
    }

    fun leave(quiet: Boolean = false) {
        if (_state.value.joined) leaving = true
        Session.scope.launch {
            lock.withLock {
                try {
                    if (!_state.value.joined) return@launch
                    runCatching { request(JSONObject().put("op", "leave")) }
                    cleanup()
                    if (!quiet) Announcer.announce("أنت خارج المحادثة الصوتية")
                } finally { leaving = false }
            }
        }
    }

    /** عند الخروج من شاشة الطاولة: نغادر المحادثة بهدوء */
    fun dispose() { leave(quiet = true); tableId = null }

    /** فتح/كتم الميكروفون. أول فتح يطلب إذن الميكروفون وينشره في الجلسة */
    fun setMuted(muted: Boolean) {
        if (!_state.value.joined) return
        // كتمه مالك الطاولة: لا يستطيع فتح الميكروفون حتى يلغي المالك الكتم
        if (!muted && members.find { it.uid == myUid }?.blocked == true) {
            Announcer.announce("كتمك مالك الطاولة، لا يمكنك فتح الميكروفون الآن"); return
        }
        mic?.let { track ->
            track.setEnabled(!muted)
            set { copy(muted = muted) }
            Announcer.announce(if (muted) "الميكروفون مغلق" else "الميكروفون مفتوح")
            Session.scope.launch { runCatching { request(JSONObject().put("op", "mute").put("sessionId", sessionId).put("muted", muted)) } }
            return
        }
        if (muted) return
        Session.scope.launch {
            lock.withLock {
                val conn = pc ?: return@launch
                if (sessionId == null || mic != null) return@launch
                set { copy(busy = true) }
                try {
                    val granted = MainActivity.current?.requestMicPermission() ?: false
                    if (!granted) {
                        set { copy(busy = false, muted = true) }
                        Announcer.announce("لم يُسمح باستخدام الميكروفون. فعّله من إعدادات الجهاز للتطبيق")
                        return@launch
                    }
                    val source = factory.createAudioSource(MediaConstraints())
                    micSource = source
                    val track = factory.createAudioTrack("mic", source)
                    mic = track
                    val tx = conn.addTransceiver(track, RtpTransceiver.RtpTransceiverInit(RtpTransceiver.RtpTransceiverDirection.SEND_ONLY))
                    val offer = conn.createOfferAwait()
                    conn.setLocalAwait(offer)
                    val r = request(JSONObject().put("op", "publish").put("sessionId", sessionId).put("offer", desc(offer)).put("mid", tx.mid))
                    // الخادم أنشأ جلسة جديدة (انتهت جلسة الاستماع لخمولها)
                    r.optString("sessionId").takeIf { it.isNotEmpty() }?.let { sessionId = it }
                    conn.setRemoteAwait(parseDesc(r.getJSONObject("answer"))!!)
                    set { copy(muted = false, busy = false) }
                    MainActivity.current?.requestNotificationsOnce()
                    background(on = true, withMic = true)
                    Announcer.announce("الميكروفون مفتوح")
                } catch (e: Exception) {
                    // يُتخلَّص منه مع الاتصال عند المغادرة؛ هنا نوقفه فقط
                    mic?.setEnabled(false); mic = null
                    set { copy(busy = false, muted = true) }
                    Announcer.announce("تعذّر فتح الميكروفون، حاول مرة أخرى")
                }
            }
        }
    }

    /** يطابق الأصوات المسحوبة مع قائمة المنضمين: يسحب الجدد ويغلق من غادر */
    fun sync(list: List<VoiceMember>) {
        members = list
        val s = _state.value
        if (!s.joined || s.busy) return
        // لسنا في قائمة الخادم: قد تكون حالة قديمة وصلت قبل تسجيل انضمامنا، أو أخرجنا الخادم فعلاً.
        // نتحقق بعد مهلة من آخر قائمة وصلت، ثم نعود مكتومين.
        if (members.none { it.uid == myUid }) {
            if (!leaving && missingJob == null) missingJob = Session.scope.launch {
                delay(4000)
                missingJob = null
                val st = _state.value
                if (st.joined && !st.busy && !leaving && members.none { it.uid == myUid }) rejoin()
            }
            return
        }
        missingJob?.cancel(); missingJob = null
        // كتمني المالك وميكروفوني مفتوح: نغلقه فوراً
        if (members.find { it.uid == myUid }?.blocked == true && mic != null && !s.muted) {
            mic?.setEnabled(false)
            set { copy(muted = true) }
            Announcer.announce("كتمك مالك الطاولة في المحادثة الصوتية")
        }
        Session.scope.launch {
            lock.withLock {
                val conn = pc ?: return@launch
                if (sessionId == null) return@launch
                // المفتاح uid + الجلسة: من أعاد الانضمام بجلسة جديدة نسحب صوته من جديد
                val others = members.filter { it.uid != myUid && it.mic && !it.blocked }.associateBy { "${it.uid}:${it.sessionId}" }
                val gone = pulled.keys.filter { it !in others }
                if (gone.isNotEmpty()) {
                    val mids = gone.mapNotNull { pulled.remove(it) }
                    runCatching { request(JSONObject().put("op", "close").put("sessionId", sessionId).put("mids", org.json.JSONArray(mids))) }
                }
                for ((key, m) in others) {
                    if (key in pulled) continue
                    try {
                        val r = request(JSONObject().put("op", "pull").put("sessionId", sessionId).put("uid", m.uid))
                        r.optString("sessionId").takeIf { it.isNotEmpty() }?.let { sessionId = it }
                        val mid = r.optJSONArray("tracks").objects().firstOrNull()?.optString("mid")?.takeIf { it.isNotEmpty() } ?: continue
                        pulled[key] = mid
                        val offer = parseDesc(r.optJSONObject("sessionDescription"))
                        if (r.optBoolean("requiresImmediateRenegotiation") && offer != null) {
                            conn.setRemoteAwait(offer)
                            val answer = conn.createAnswerAwait()
                            conn.setLocalAwait(answer)
                            request(JSONObject().put("op", "renegotiate").put("sessionId", sessionId).put("answer", desc(answer)))
                        }
                    } catch (_: Exception) { /* نحاول مع التحديث التالي */ }
                }
            }
        }
    }

    /** بعد مكالمة هاتفية قد ينقطع اتصال الصوت: نصلحه عند العودة للتطبيق */
    fun onResume() {
        val s = _state.value
        if (!s.joined || s.busy) return
        val st = pc?.connectionState()
        if (pc == null || st == PeerConnection.PeerConnectionState.FAILED || st == PeerConnection.PeerConnectionState.CLOSED) rejoin()
    }

    private fun rejoin() {
        if (rejoining || leaving) return
        val id = tableId ?: return
        rejoining = true
        set { copy(reconnecting = true) }
        Session.scope.launch {
            lock.withLock { cleanup() }
            join(id, myUid, Mode.Rejoin)
            delay(1000)
            rejoining = false
        }
    }

    private fun cleanup() {
        missingJob?.cancel(); missingJob = null
        pulled.clear()
        // الاتصال أولاً ثم الميكروفون ومصدره (المكتبة لا تتخلص من المسار المضاف بنفسها)
        pc?.let { runCatching { it.dispose() } }
        pc = null
        mic?.let { runCatching { it.dispose() } }
        mic = null
        micSource?.let { runCatching { it.dispose() } }
        micSource = null
        sessionId = null
        audio(false)
        background(on = false, withMic = false)
        set { State(reconnecting = reconnecting) }
    }

    // ───── الصوت في الجهاز ─────

    private var focus: AudioFocusRequest? = null
    private var savedMode = AudioManager.MODE_NORMAL

    /**
     * أثناء المحادثة: الصوت من مكبر الجهاز (لا السماعة الصغيرة)، ونمسك تركيز الصوت ونطلب ألا يخفضنا النظام
     * حين يتكلم TalkBack، فيبقى صوت اللاعبين بنفس المستوى.
     */
    private fun audio(on: Boolean) {
        val am = ctx.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        if (on) {
            savedMode = am.mode
            am.mode = AudioManager.MODE_IN_COMMUNICATION
            if (Build.VERSION.SDK_INT >= 31) {
                am.availableCommunicationDevices.firstOrNull { it.type == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER }?.let { am.setCommunicationDevice(it) }
            } else {
                @Suppress("DEPRECATION")
                am.isSpeakerphoneOn = true
            }
            if (Build.VERSION.SDK_INT >= 26 && focus == null) {
                focus = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
                    .setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION).setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build())
                    .setWillPauseWhenDucked(true)
                    .setOnAudioFocusChangeListener { }
                    .build()
                    .also { am.requestAudioFocus(it) }
            }
            background(on = true, withMic = false)
        } else {
            if (Build.VERSION.SDK_INT >= 31) am.clearCommunicationDevice() else {
                @Suppress("DEPRECATION")
                am.isSpeakerphoneOn = false
            }
            am.mode = savedMode
            if (Build.VERSION.SDK_INT >= 26) focus?.let { am.abandonAudioFocusRequest(it) }
            focus = null
        }
    }

    /** تشغيل المحادثة في الخلفية (خدمة أمامية بإشعار ثابت) أو إيقافها */
    private fun background(on: Boolean, withMic: Boolean) {
        val i = Intent(ctx, VoiceService::class.java).putExtra("mic", withMic)
        runCatching { if (on) ContextCompat.startForegroundService(ctx, i) else ctx.stopService(i) }
    }
}

// ───── مساعدات WebRTC ─────

private open class SdpAdapter : SdpObserver {
    override fun onCreateSuccess(p0: SessionDescription?) {}
    override fun onSetSuccess() {}
    override fun onCreateFailure(p0: String?) {}
    override fun onSetFailure(p0: String?) {}
}

private suspend fun PeerConnection.createOfferAwait(): SessionDescription = suspendCancellableCoroutine { c ->
    createOffer(object : SdpAdapter() {
        override fun onCreateSuccess(p0: SessionDescription?) { c.resume(p0!!) }
        override fun onCreateFailure(p0: String?) { c.resumeWithException(ApiError("sdp")) }
    }, MediaConstraints())
}

private suspend fun PeerConnection.createAnswerAwait(): SessionDescription = suspendCancellableCoroutine { c ->
    createAnswer(object : SdpAdapter() {
        override fun onCreateSuccess(p0: SessionDescription?) { c.resume(p0!!) }
        override fun onCreateFailure(p0: String?) { c.resumeWithException(ApiError("sdp")) }
    }, MediaConstraints())
}

private suspend fun PeerConnection.setLocalAwait(d: SessionDescription): Unit = suspendCancellableCoroutine { c ->
    setLocalDescription(object : SdpAdapter() {
        override fun onSetSuccess() { c.resume(Unit) }
        override fun onSetFailure(p0: String?) { c.resumeWithException(ApiError("sdp")) }
    }, d)
}

private suspend fun PeerConnection.setRemoteAwait(d: SessionDescription): Unit = suspendCancellableCoroutine { c ->
    setRemoteDescription(object : SdpAdapter() {
        override fun onSetSuccess() { c.resume(Unit) }
        override fun onSetFailure(p0: String?) { c.resumeWithException(ApiError("sdp")) }
    }, d)
}

/** الأصوات الواردة تُشغَّل تلقائياً عبر مكتبة WebRTC (لا نحتاج أكثر من مراقبة الاتصال) */
private open class PeerObserver : PeerConnection.Observer {
    override fun onSignalingChange(p0: PeerConnection.SignalingState?) {}
    override fun onIceConnectionChange(p0: PeerConnection.IceConnectionState?) {}
    override fun onIceConnectionReceivingChange(p0: Boolean) {}
    override fun onIceGatheringChange(p0: PeerConnection.IceGatheringState?) {}
    override fun onIceCandidate(p0: org.webrtc.IceCandidate?) {}
    override fun onIceCandidatesRemoved(p0: Array<out org.webrtc.IceCandidate>?) {}
    override fun onAddStream(p0: MediaStream?) {}
    override fun onRemoveStream(p0: MediaStream?) {}
    override fun onDataChannel(p0: org.webrtc.DataChannel?) {}
    override fun onRenegotiationNeeded() {}
    override fun onAddTrack(p0: RtpReceiver?, p1: Array<out MediaStream>?) {}
}
