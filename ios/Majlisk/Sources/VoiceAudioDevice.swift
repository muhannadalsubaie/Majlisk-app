import Foundation
import AVFoundation
import AudioToolbox
import WebRTC

/**
 * جهاز الصوت للمحادثة الصوتية (بدل جهاز WebRTC الافتراضي): وحدة معالجة صوت المكالمات من Apple
 * (إلغاء الصدى)، لكن بإعداداتنا:
 *  • "خفض الأصوات الثانية" على أقل مستوى (iOS 17+): الورق والتعليق وVoiceOver تبقى بصوتها حتى والميكروفون مفتوح.
 *  • وأنت تسمع بس (الميكروفون مقفل): المعالجة نفسها مطفأة، فما يتأثر أي صوت أبداً.
 * وفي iOS 18.2 وأحدث: بدل وحدة المكالمات نستخدم وحدة الصوت العادية مع "إلغاء الصدى من النظام"
 * (prefersEchoCancelledInput)، فما فيه أي خفض للأصوات أبداً، لا والميكروفون مقفل ولا مفتوح.
 * الصوت PCM ‏16-بت أحادي، WebRTC يسحب الصوت للتشغيل ونسلّمه صوت الميكروفون.
 */
final class VoiceAudioDevice: NSObject, RTCAudioDevice {
    /// جهاز الصوت الشغّال الآن (المحادثة الصوتية فيها): أصوات اللعب تنخلط فيه بدل ما تشتغل لحالها،
    /// فما يعتبرها النظام "صوت ثاني" يخفضه، وتنلغى من الميكروفون مع صوت الباقين (ما يسمعونها منك)
    private(set) static weak var active: VoiceAudioDevice?
    /// أصوات اللعب المخلوطة مع صوت المحادثة
    let effects = EffectMixer()
    private var unit: AudioUnit?
    private weak var delegate: RTCAudioDeviceDelegate?

    private(set) var isInitialized = false
    private(set) var isPlayoutInitialized = false
    private(set) var isPlaying = false
    private(set) var isRecordingInitialized = false
    private(set) var isRecording = false
    /// الميكروفون مفتوح وتتكلم: نشغّل المعالجة (إلغاء الصدى)
    private var talking = false
    /// ذاكرة لتسجيل الميكروفون
    private var recordBuffer = [Int16](repeating: 0, count: 4096)

    private var session: AVAudioSession { AVAudioSession.sharedInstance() }
    /// iOS 18.2+: إلغاء الصدى من النظام نفسه على الوحدة العادية (بلا وحدة المكالمات اللي تخفض الأصوات)
    private var systemEcho: Bool {
        if #available(iOS 18.2, *) { return session.isEchoCancelledInputAvailable }
        return false
    }
    /// إلغاء الصدى من النظام اشتغل فعلاً (نتأكد بعد طلبه): لو ما اشتغل نستخدم وحدة المكالمات،
    /// وإلا يرجع صوت الباقين لهم ويسمعون قارئ الشاشة من جوالك
    private var systemEchoOn = false
    /// الوحدة الحالية: العادية (RemoteIO) أو وحدة المكالمات (VoiceProcessingIO)
    private var plainUnit = false
    var deviceInputSampleRate: Double { session.sampleRate }
    var inputIOBufferDuration: TimeInterval { session.ioBufferDuration }
    var inputNumberOfChannels: Int { 1 }
    var inputLatency: TimeInterval { session.inputLatency }
    var deviceOutputSampleRate: Double { session.sampleRate }
    var outputIOBufferDuration: TimeInterval { session.ioBufferDuration }
    var outputNumberOfChannels: Int { 1 }
    var outputLatency: TimeInterval { session.outputLatency }

    func initialize(with delegate: RTCAudioDeviceDelegate) -> Bool {
        self.delegate = delegate
        isInitialized = true
        return true
    }

    func terminateDevice() -> Bool {
        _ = stopRecording()
        _ = stopPlayout()
        disposeUnit()
        isInitialized = false
        return true
    }

    func initializePlayout() -> Bool {
        if unit == nil && !makeUnit(input: false) { return false }
        isPlayoutInitialized = true
        return true
    }

    func startPlayout() -> Bool {
        guard let unit else { return false }
        isPlaying = true
        effects.setRate(session.sampleRate)
        // نحوّل كل أصوات اللعب مسبقاً في الخلفية: التحويل وقت التشغيل كان على الخيط الرئيسي فيعلّق VoiceOver
        DispatchQueue.main.async { [effects] in effects.prewarm(Sounds.shared.allFiles()) }
        let ok = AudioOutputUnitStart(unit) == noErr
        if ok { VoiceAudioDevice.active = self }
        return ok
    }

    func stopPlayout() -> Bool {
        isPlaying = false
        if VoiceAudioDevice.active === self { VoiceAudioDevice.active = nil }
        effects.clear()
        if !isRecording, let unit { AudioOutputUnitStop(unit) }
        return true
    }

    func initializeRecording() -> Bool {
        // الميكروفون ينفتح أول مرة: نعيد بناء الوحدة مع الإدخال (قبلها ما نطلب الميكروفون أبداً)
        let wasPlaying = isPlaying
        systemEchoOn = false
        disposeUnit()
        // إلغاء الصدى من وحدة المكالمات (مو من النظام): نطفّي تفضيل النظام عشان ما تنعالج مرتين
        if #available(iOS 18.2, *), session.isEchoCancelledInputAvailable { try? session.setPrefersEchoCancelledInput(false) }
        guard makeUnit(input: true) else { return false }
        isRecordingInitialized = true
        if wasPlaying, let unit { AudioOutputUnitStart(unit) }
        return true
    }

    func startRecording() -> Bool {
        guard let unit else { return false }
        isRecording = true
        setTalking(true)
        if !isPlaying { return AudioOutputUnitStart(unit) == noErr }
        return true
    }

    func stopRecording() -> Bool {
        isRecording = false
        setTalking(false)
        if !isPlaying, let unit { AudioOutputUnitStop(unit) }
        return true
    }

    /// يتكلم (الميكروفون مفتوح) أو يسمع بس: المعالجة تشتغل أو تنطفئ بدون إعادة اتصال
    func setTalking(_ on: Bool) {
        talking = on
        guard let unit, !plainUnit else { return }
        var bypass: UInt32 = on ? 0 : 1
        AudioUnitSetProperty(unit, kAUVoiceIOProperty_BypassVoiceProcessing, kAudioUnitScope_Global, 0, &bypass, UInt32(MemoryLayout<UInt32>.size))
    }

    // ───── وحدة الصوت ─────

    private func makeUnit(input: Bool) -> Bool {
        // iOS 18.2+: الوحدة العادية دائماً (إلغاء الصدى من النظام وقت الكلام) — بلا أي خفض للأصوات
        // مع الميكروفون: الوحدة العادية بس لو إلغاء الصدى من النظام اشتغل فعلاً، وإلا وحدة المكالمات (تلغي الصدى أكيد)
        // بدون ميكروفون: الوحدة العادية (ما تحتاج إلغاء صدى، وتشتغل مع وضع الوسائط فيطلع الصوت من السماعتين).
        // مع الميكروفون: وحدة المكالمات من Apple دائماً — إلغاء الصدى «من النظام» في iOS 26 و27 يقول إنه شغّال
        // وفي بعض الأجهزة ما يلغي الصدى فعلياً. أصوات اللعبة تمر في نفس الوحدة فما تنخفض وما يسمعها الباقين
        let plain = !input
        var desc = AudioComponentDescription(componentType: kAudioUnitType_Output, componentSubType: plain ? kAudioUnitSubType_RemoteIO : kAudioUnitSubType_VoiceProcessingIO,
                                             componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0)
        guard let comp = AudioComponentFindNext(nil, &desc) else { return false }
        var u: AudioUnit?
        guard AudioComponentInstanceNew(comp, &u) == noErr, let u else { return false }

        var one: UInt32 = 1
        let zero: UInt32 = 0
        let size = UInt32(MemoryLayout<UInt32>.size)
        // الإخراج (السماعة) دائماً، والإدخال (الميكروفون) بس لما تفتحه
        AudioUnitSetProperty(u, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0, &one, size)
        var inputOn: UInt32 = input ? one : zero
        AudioUnitSetProperty(u, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1, &inputOn, size)

        var fmt = AudioStreamBasicDescription(mSampleRate: session.sampleRate, mFormatID: kAudioFormatLinearPCM,
                                              mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
                                              mBytesPerPacket: 2, mFramesPerPacket: 1, mBytesPerFrame: 2, mChannelsPerFrame: 1,
                                              mBitsPerChannel: 16, mReserved: 0)
        let fsize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        AudioUnitSetProperty(u, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &fmt, fsize)
        if input { AudioUnitSetProperty(u, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1, &fmt, fsize) }

        let me = Unmanaged.passUnretained(self).toOpaque()
        var render = AURenderCallbackStruct(inputProc: { refCon, flags, ts, bus, frames, data in
            let dev = Unmanaged<VoiceAudioDevice>.fromOpaque(refCon).takeUnretainedValue()
            return dev.playout(flags, ts, bus, frames, data)
        }, inputProcRefCon: me)
        AudioUnitSetProperty(u, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &render, UInt32(MemoryLayout<AURenderCallbackStruct>.size))
        if input {
            var rec = AURenderCallbackStruct(inputProc: { refCon, flags, ts, bus, frames, _ in
                let dev = Unmanaged<VoiceAudioDevice>.fromOpaque(refCon).takeUnretainedValue()
                return dev.recorded(flags, ts, bus, frames)
            }, inputProcRefCon: me)
            AudioUnitSetProperty(u, kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Global, 1, &rec, UInt32(MemoryLayout<AURenderCallbackStruct>.size))
        }

        // "خفض الأصوات الثانية" على أقل مستوى: الورق والتعليق وVoiceOver ما تنخفض وأنت تتكلم
        if !plain, #available(iOS 17.0, *) {
            var duck = AUVoiceIOOtherAudioDuckingConfiguration(mEnableAdvancedDucking: false, mDuckingLevel: .min)
            AudioUnitSetProperty(u, kAUVoiceIOProperty_OtherAudioDuckingConfiguration, kAudioUnitScope_Global, 0, &duck,
                                 UInt32(MemoryLayout<AUVoiceIOOtherAudioDuckingConfiguration>.size))
        }
        // المعالجة مطفأة وأنت تسمع بس
        if !plain {
            var bypass: UInt32 = talking ? 0 : 1
            AudioUnitSetProperty(u, kAUVoiceIOProperty_BypassVoiceProcessing, kAudioUnitScope_Global, 0, &bypass, size)
        }

        guard AudioUnitInitialize(u) == noErr else { AudioComponentInstanceDispose(u); return false }
        unit = u
        plainUnit = plain
        return true
    }

    private func disposeUnit() {
        guard let u = unit else { return }
        AudioOutputUnitStop(u)
        AudioUnitUninitialize(u)
        AudioComponentInstanceDispose(u)
        unit = nil
        isPlayoutInitialized = false
        isRecordingInitialized = false
    }

    /// WebRTC يعطينا صوت الباقين للتشغيل
    private func playout(_ flags: UnsafeMutablePointer<AudioUnitRenderActionFlags>, _ ts: UnsafePointer<AudioTimeStamp>,
                         _ bus: UInt32, _ frames: UInt32, _ data: UnsafeMutablePointer<AudioBufferList>?) -> OSStatus {
        guard let data else { return noErr }
        let list = UnsafeMutableAudioBufferListPointer(data)
        guard isPlaying, let delegate else {
            for b in list { if let p = b.mData { memset(p, 0, Int(b.mDataByteSize)) } }
            return noErr
        }
        let st = delegate.getPlayoutData(flags, ts, Int(bus), frames, data)
        // أصوات اللعب فوق صوت المحادثة، بنفس المستوى
        if let p = list.first?.mData { effects.mix(into: p.assumingMemoryBound(to: Int16.self), frames: Int(frames)) }
        return st
    }

    /// صوت الميكروفون: نقرأه من الوحدة ونسلّمه لـ WebRTC
    private func recorded(_ flags: UnsafeMutablePointer<AudioUnitRenderActionFlags>, _ ts: UnsafePointer<AudioTimeStamp>,
                          _ bus: UInt32, _ frames: UInt32) -> OSStatus {
        guard isRecording, let unit, let delegate else { return noErr }
        let count = Int(frames)
        if recordBuffer.count < count { recordBuffer = [Int16](repeating: 0, count: count) }
        return recordBuffer.withUnsafeMutableBytes { raw -> OSStatus in
            var list = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(count * 2), mData: raw.baseAddress))
            let st = AudioUnitRender(unit, flags, ts, bus, frames, &list)
            guard st == noErr else { return st }
            return delegate.deliverRecordedData(flags, ts, Int(bus), frames, &list, nil, nil)
        }
    }
}

/// خلاط أصوات اللعب داخل جهاز صوت المحادثة: كل صوت PCM ‏16-بت أحادي بنفس تردد الجهاز
final class EffectMixer {
    private struct Playing { let samples: [Int16]; var pos: Int; let gain: Float }
    private let lock = NSLock()
    private var playing: [Playing] = []
    /// التحويل (فك mp3) في خيط خلفي، مو على الخيط الرئيسي: كان يعلّق قارئ الشاشة وأنت في المحادثة
    private let work = DispatchQueue(label: "majlisk.effects", qos: .userInitiated)
    private var cache: [String: [Int16]] = [:]
    /// تردد جهاز الصوت (يتغير مع السماعة) — يُقرأ ويُكتب في خيط التحويل بس
    private var rate: Double = 48000

    func setRate(_ r: Double) {
        work.async { if r != self.rate { self.rate = r; self.cache.removeAll() } }
    }

    func prewarm(_ files: [(String, URL)]) {
        work.async { for (n, u) in files { _ = self.samples(n, u) } }
    }

    /// يحوّل ملف الصوت مرة وحدة لتردد الجهاز
    private func samples(_ name: String, _ url: URL) -> [Int16]? {
        if let c = cache[name] { return c }
        guard let file = try? AVAudioFile(forReading: url),
              let out = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: rate, channels: 1, interleaved: true),
              let conv = AVAudioConverter(from: file.processingFormat, to: out),
              let src = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else { return nil }
        do { try file.read(into: src) } catch { return nil }
        let cap = AVAudioFrameCount(Double(src.frameLength) * rate / file.processingFormat.sampleRate) + 1024
        guard let dst = AVAudioPCMBuffer(pcmFormat: out, frameCapacity: cap) else { return nil }
        var fed = false
        var err: NSError?
        conv.convert(to: dst, error: &err) { _, status in
            if fed { status.pointee = .endOfStream; return nil }
            fed = true; status.pointee = .haveData; return src
        }
        guard err == nil, let ch = dst.int16ChannelData else { return nil }
        let arr = Array(UnsafeBufferPointer(start: ch[0], count: Int(dst.frameLength)))
        cache[name] = arr
        return arr
    }

    func play(_ name: String, url: URL, gain: Float) {
        work.async {
            guard let s = self.samples(name, url) else { return }
            self.lock.lock()
            self.playing.append(Playing(samples: s, pos: 0, gain: gain))
            if self.playing.count > 12 { self.playing.removeFirst() }
            self.lock.unlock()
        }
    }

    func clear() {
        lock.lock()
        playing.removeAll()
        lock.unlock()
    }

    /// يُستدعى من خيط الصوت: يضيف الأصوات الشغّالة فوق صوت المحادثة
    func mix(into out: UnsafeMutablePointer<Int16>, frames: Int) {
        guard lock.try() else { return }
        defer { lock.unlock() }
        if playing.isEmpty { return }
        for i in playing.indices {
            let p = playing[i]
            let n = min(frames, p.samples.count - p.pos)
            if n <= 0 { continue }
            p.samples.withUnsafeBufferPointer { b in
                for f in 0..<n {
                    let v = Int32(out[f]) + Int32(Float(b[p.pos + f]) * p.gain)
                    out[f] = Int16(clamping: v)
                }
            }
            playing[i].pos += n
        }
        playing.removeAll { $0.pos >= $0.samples.count }
    }
}
