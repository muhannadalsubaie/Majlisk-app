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
        return AudioOutputUnitStart(unit) == noErr
    }

    func stopPlayout() -> Bool {
        isPlaying = false
        if !isRecording, let unit { AudioOutputUnitStop(unit) }
        return true
    }

    func initializeRecording() -> Bool {
        // الميكروفون ينفتح أول مرة: نعيد بناء الوحدة مع الإدخال (قبلها ما نطلب الميكروفون أبداً)
        let wasPlaying = isPlaying
        if #available(iOS 18.2, *), session.isEchoCancelledInputAvailable { try? session.setPrefersEchoCancelledInput(true) }
        disposeUnit()
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
        let plain = systemEcho
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
        guard isPlaying, let delegate else {
            for b in UnsafeMutableAudioBufferListPointer(data) { if let p = b.mData { memset(p, 0, Int(b.mDataByteSize)) } }
            return noErr
        }
        return delegate.getPlayoutData(flags, ts, Int(bus), frames, data)
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
