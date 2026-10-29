import Foundation
import AVFoundation
import WebRTC

/**
 * المحادثة الصوتية للطاولة عبر Cloudflare Realtime (WebRTC) — نفس طريقة التطبيق الحالي:
 * كل شخص ينشر ميكروفونه في جلسة خاصة به، ويسحب أصوات بقية المنضمين إلى نفس الاتصال.
 * الخادم (غرفة الطاولة) يمرر الطلبات ويتحقق أن الشخص في الطاولة ويملك جلسته.
 * يبدأ الميكروفون مكتوماً دائماً (استماع فقط)، والكتم محلي دون إعادة تفاوض.
 */
final class Voice: NSObject, ObservableObject, RTCPeerConnectionDelegate {
    enum Mode { case manual, auto, rejoin }
    static let shared = Voice()

    @Published private(set) var joined = false
    @Published private(set) var muted = true
    @Published private(set) var busy = false

    private lazy var factory: RTCPeerConnectionFactory = {
        RTCInitializeSSL()
        // الصوت من مكبر الجهاز (لا السماعة الصغيرة)، ويمتزج مع VoiceOver
        let cfg = RTCAudioSessionConfiguration.webRTC()
        cfg.categoryOptions = [.defaultToSpeaker, .allowBluetoothHFP, .mixWithOthers]
        RTCAudioSessionConfiguration.setWebRTC(cfg)
        return RTCPeerConnectionFactory(encoderFactory: RTCDefaultVideoEncoderFactory(), decoderFactory: RTCDefaultVideoDecoderFactory())
    }()
    private var tableId: String?
    private var myUid = ""
    private var pc: RTCPeerConnection?
    private var mic: RTCAudioTrack?
    private var sessionId: String?
    /// من أسحب صوته: uid:session → mid
    private var pulled: [String: String] = [:]
    private var members: [VoiceMember] = []
    private var leaving = false
    private var rejoining = false
    private var autoRetries = 0
    private var missingTask: Task<Void, Never>?
    /// كل عمليات التفاوض متسلسلة (WebRTC لا يقبل عرضين في نفس اللحظة)
    private let queue = SerialQueue()

    private func set(joined: Bool? = nil, muted: Bool? = nil, busy: Bool? = nil) {
        DispatchQueue.main.async {
            if let joined { self.joined = joined }
            if let muted { self.muted = muted }
            if let busy { self.busy = busy }
        }
    }
    private var isJoined = false, isMuted = true, isBusy = false

    private func request(_ body: JSON) async throws -> JSON {
        try await Api.post("/tables/\(tableId ?? "")/voice", body)
    }
    private func desc(_ d: RTCSessionDescription) -> JSON {
        ["type": d.type == .offer ? "offer" : "answer", "sdp": d.sdp]
    }
    private func parseDesc(_ o: JSON?) -> RTCSessionDescription? {
        guard let o, let sdp = o["sdp"] as? String else { return nil }
        return RTCSessionDescription(type: o.str("type") == "offer" ? .offer : .answer, sdp: sdp)
    }

    private func update(joined: Bool? = nil, muted: Bool? = nil, busy: Bool? = nil) {
        if let joined { isJoined = joined }
        if let muted { isMuted = muted }
        if let busy { isBusy = busy }
        set(joined: joined, muted: muted, busy: busy)
    }

    /// الانضمام: جلسة استماع فقط بلا ميكروفون — لا يُطلب إذن الميكروفون حتى تفتحه بنفسك
    func join(_ id: String, uid: String, mode: Mode = .manual) {
        queue.run { [self] in
            if isJoined || isBusy { return }
            update(busy: true)
            tableId = id
            myUid = uid
            do {
                configureAudio(listening: true)
                let config = RTCConfiguration()
                config.iceServers = [RTCIceServer(urlStrings: ["stun:stun.cloudflare.com:3478"])]
                config.bundlePolicy = .maxBundle
                config.sdpSemantics = .unifiedPlan
                guard let conn = factory.peerConnection(with: config, constraints: RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil), delegate: self) else { throw ApiError(code: "voice-failed") }
                pc = conn
                let r = try await request(["op": "session"])
                sessionId = r.str("sessionId")
                members = members.filter { $0.uid != uid } + [VoiceMember(uid: uid, username: "", sessionId: sessionId!, muted: true, mic: false, blocked: false)]
                update(joined: true, muted: true, busy: false)
                autoRetries = 0
                if mode != .rejoin { Announcer.announce("أنت في المحادثة الصوتية تسمع الآخرين، والميكروفون مغلق. اضغط زر الميكروفون لفتحه") }
            } catch {
                cleanup()
                let code = (error as? ApiError)?.code
                // الانضمام التلقائي يفشل بصمت، ويعيد المحاولة بعد قليل إن كان الخطأ عابراً
                if mode != .manual && code != "voice-not-configured" && code != "voice-limit" && autoRetries < 3 {
                    autoRetries += 1
                    let wait = UInt64(5_000_000_000 * autoRetries)
                    Task { try? await Task.sleep(nanoseconds: wait); if !self.isJoined && self.tableId == id { self.join(id, uid: uid, mode: mode) } }
                }
                if mode == .manual {
                    Announcer.announce(code == "voice-not-configured" ? "المحادثة الصوتية غير مفعّلة بعد"
                        : code == "voice-limit" ? "المحادثة الصوتية وصلت لحدها هذا الشهر، وترجع بداية الشهر الجاي"
                        : "تعذّر الانضمام للمحادثة الصوتية، حاول مرة أخرى")
                }
                return
            }
            self.syncNow()
        }
    }

    func leave(quiet: Bool = false) {
        if isJoined { leaving = true }
        queue.run { [self] in
            defer { leaving = false }
            if !isJoined { return }
            _ = try? await request(["op": "leave"])
            cleanup()
            if !quiet { Announcer.announce("أنت خارج المحادثة الصوتية") }
        }
    }

    /// عند الخروج من شاشة الطاولة: نغادر المحادثة بهدوء
    func dispose() { leave(quiet: true) }

    /// فتح/كتم الميكروفون. أول فتح يطلب إذن الميكروفون وينشره في الجلسة
    func setMuted(_ m: Bool) {
        guard isJoined else { return }
        // كتمه مالك الطاولة: لا يستطيع فتح الميكروفون حتى يلغي المالك الكتم
        if !m && members.first(where: { $0.uid == myUid })?.blocked == true {
            Announcer.announce("كتمك مالك الطاولة، لا يمكنك فتح الميكروفون الآن"); return
        }
        if let mic {
            mic.isEnabled = !m
            update(muted: m)
            Announcer.announce(m ? "الميكروفون مغلق" : "الميكروفون مفتوح")
            let sid = sessionId
            Task { _ = try? await request(["op": "mute", "sessionId": sid ?? "", "muted": m]) }
            return
        }
        if m { return }
        queue.run { [self] in
            guard let conn = pc, sessionId != nil, mic == nil else { return }
            update(busy: true)
            let granted = await withCheckedContinuation { c in AVAudioSession.sharedInstance().requestRecordPermission { c.resume(returning: $0) } }
            if !granted {
                update(muted: true, busy: false)
                Announcer.announce("لم يُسمح باستخدام الميكروفون. فعّله من إعدادات الجهاز للتطبيق")
                return
            }
            do {
                configureAudio(listening: false)
                let source = factory.audioSource(with: RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil))
                let track = factory.audioTrack(with: source, trackId: "mic")
                mic = track
                let initTx = RTCRtpTransceiverInit()
                initTx.direction = .sendOnly
                guard let tx = conn.addTransceiver(with: track, init: initTx) else { throw ApiError(code: "voice-failed") }
                let offer = try await conn.offer(for: RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil))
                try await conn.setLocalDescription(offer)
                let r = try await request(["op": "publish", "sessionId": sessionId ?? "", "offer": desc(offer), "mid": tx.mid])
                // الخادم أنشأ جلسة جديدة (انتهت جلسة الاستماع لخمولها)
                if let s = r.strOrNil("sessionId"), !s.isEmpty { sessionId = s }
                guard let answer = parseDesc(r.obj("answer")) else { throw ApiError(code: "voice-failed") }
                try await conn.setRemoteDescription(answer)
                update(muted: false, busy: false)
                Announcer.announce("الميكروفون مفتوح")
            } catch {
                mic?.isEnabled = false
                mic = nil
                update(muted: true, busy: false)
                Announcer.announce("تعذّر فتح الميكروفون، حاول مرة أخرى")
            }
        }
    }

    /// يطابق الأصوات المسحوبة مع قائمة المنضمين: يسحب الجدد ويغلق من غادر
    func sync(_ list: [VoiceMember]) {
        members = list
        guard isJoined, !isBusy else { return }
        // لسنا في قائمة الخادم: قد تكون حالة قديمة، أو أخرجنا الخادم فعلاً — نتحقق بعد مهلة ثم نعود مكتومين
        if !members.contains(where: { $0.uid == myUid }) {
            if !leaving && missingTask == nil {
                missingTask = Task {
                    try? await Task.sleep(nanoseconds: 4_000_000_000)
                    self.missingTask = nil
                    if self.isJoined && !self.isBusy && !self.leaving && !self.members.contains(where: { $0.uid == self.myUid }) { self.rejoin() }
                }
            }
            return
        }
        missingTask?.cancel(); missingTask = nil
        // كتمني المالك وميكروفوني مفتوح: نغلقه فوراً
        if members.first(where: { $0.uid == myUid })?.blocked == true, let mic, !isMuted {
            mic.isEnabled = false
            update(muted: true)
            Announcer.announce("كتمك مالك الطاولة في المحادثة الصوتية")
        }
        syncNow()
    }

    private func syncNow() {
        queue.run { [self] in
            guard let conn = pc, sessionId != nil else { return }
            // المفتاح uid + الجلسة: من أعاد الانضمام بجلسة جديدة نسحب صوته من جديد
            var others: [String: VoiceMember] = [:]
            for m in members where m.uid != myUid && m.mic && !m.blocked { others["\(m.uid):\(m.sessionId)"] = m }
            let gone = pulled.keys.filter { others[$0] == nil }
            if !gone.isEmpty {
                let mids = gone.compactMap { pulled.removeValue(forKey: $0) }
                _ = try? await request(["op": "close", "sessionId": sessionId ?? "", "mids": mids])
            }
            for (key, m) in others where pulled[key] == nil {
                do {
                    let r = try await request(["op": "pull", "sessionId": sessionId ?? "", "uid": m.uid])
                    if let s = r.strOrNil("sessionId"), !s.isEmpty { sessionId = s }
                    guard let mid = r.objs("tracks").first?.strOrNil("mid"), !mid.isEmpty else { continue }
                    pulled[key] = mid
                    if r.bool("requiresImmediateRenegotiation"), let offer = parseDesc(r.obj("sessionDescription")) {
                        try await conn.setRemoteDescription(offer)
                        let answer = try await conn.answer(for: RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil))
                        try await conn.setLocalDescription(answer)
                        _ = try await request(["op": "renegotiate", "sessionId": sessionId ?? "", "answer": desc(answer)])
                    }
                } catch { /* نحاول مع التحديث التالي */ }
            }
        }
    }

    /// بعد مكالمة هاتفية قد ينقطع اتصال الصوت: نصلحه عند العودة للتطبيق
    func onForeground() {
        guard isJoined, !isBusy else { return }
        if pc == nil || pc?.connectionState == .failed || pc?.connectionState == .closed { rejoin() }
    }

    private func rejoin() {
        guard !rejoining, !leaving, let id = tableId else { return }
        rejoining = true
        queue.run { [self] in
            cleanup()
            join(id, uid: myUid, mode: .rejoin)
            rejoining = false
        }
    }

    private func cleanup() {
        missingTask?.cancel(); missingTask = nil
        pulled.removeAll()
        pc?.close()
        pc = nil
        mic = nil
        sessionId = nil
        update(joined: false, muted: true, busy: false)
        configureAudio(listening: nil)
    }

    /// الصوت من مكبر الجهاز، ويمتزج مع VoiceOver دون أن يخفضه أحدهما
    private func configureAudio(listening: Bool?) {
        let s = AVAudioSession.sharedInstance()
        if listening == nil {
            try? s.setCategory(.playback, options: [.mixWithOthers])
            return
        }
        try? s.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetoothHFP, .mixWithOthers])
        try? s.setActive(true)
    }

    // ───── RTCPeerConnectionDelegate ─────
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCPeerConnectionState) {
        // انقطع اتصال الصوت نفسه (تغيّر الشبكة، مكالمة): نعيد الانضمام مكتومين
        if newState == .failed && peerConnection === pc && isJoined && !leaving { rejoin() }
    }
}

/// ينفّذ المهام واحدة بعد الأخرى
final class SerialQueue {
    private var tail: Task<Void, Never>?
    func run(_ work: @escaping () async -> Void) {
        let prev = tail
        tail = Task { await prev?.value; await work() }
    }
}
