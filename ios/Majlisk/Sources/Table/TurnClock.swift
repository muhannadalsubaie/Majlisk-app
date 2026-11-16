import SwiftUI

/// خيارات مؤقت الدور اللي يختارها المالك لما يبدأ المباراة (٠ = بدون وقت)
let TURN_LIMITS = [0, 10, 20, 30, 40, 50, 60]
func turnLimitLabel(_ s: Int) -> String { s == 0 ? "بدون وقت" : "\(s) ثانية" }

/// ساعة جنب اسم اللي عليه الدور: تعد تنازلياً لو المالك اختار وقت، وبدون رقم لو ما فيه وقت.
/// لك أنت: VoiceOver يقول «باقي ٥ ثواني» قبل ما يلعب عنك الروبوت
struct TurnClock: View {
    let v: TableView
    let seat: Int
    let turn: Bool
    @State private var warnedFor: Date?

    var body: some View {
        if turn {
            let deadline = v.clockLimit > 0 && v.clockSeat == seat ? v.clockDeadline : nil
            // بدون وقت: ما يتحدث أبداً. مع وقت: مرة كل ثانية بس (تحديث أقل = VoiceOver يتحرك أسرع على الطاولة)
            let start = deadline.map { $0.addingTimeInterval(-ceil($0.timeIntervalSinceNow)) } ?? .now
            TimelineView(.periodic(from: start, by: deadline == nil ? 3600 : 1)) { ctx in
                let secs = deadline.map { max(0, Int(ceil($0.timeIntervalSince(ctx.date)))) }
                HStack(spacing: 2) {
                    Text(spoken("⏱")).font(.system(size: 13))
                    if let secs {
                        Text(spoken("\(secs)")).font(.system(size: 13, weight: .bold)).foregroundColor(secs <= 5 ? Palette.goldSoft : Palette.text)
                            .onChange(of: secs) { s in
                                if s == 5, seat == v.mySeat, let d = deadline, warnedFor != d { warnedFor = d; Announcer.announce("باقي ٥ ثواني") }
                            }
                    }
                }
            }
            .accessibilityHidden(true)
        }
    }
}

/// مؤقت الدور فوق صورة اللاعب: حلقة ذهبية حول الصورة تنقص مع الوقت، والثواني الباقية في وسطها
/// (بحجم الصورة نفسها). تطلع عند اللي عليه الدور بس، وتنتقل للي بعده أول ما يلعب.
struct TurnAvatar: View {
    let v: TableView
    let seat: Int
    let turn: Bool
    let uid: String?
    let name: String
    let size: CGFloat
    @State private var warnedFor: Date?

    var body: some View {
        ZStack {
            Avatar(uid: uid, name: name, size: size)
            if turn {
                let deadline = v.clockLimit > 0 && v.clockSeat == seat ? v.clockDeadline : nil
                TimelineView(.periodic(from: .now, by: deadline == nil ? 3600 : 0.1)) { ctx in
                    let left = deadline.map { max(0, $0.timeIntervalSince(ctx.date)) }
                    let frac = left.map { v.clockLimit > 0 ? min(1, $0 / Double(v.clockLimit)) : 1 } ?? 1
                    let secs = left.map { Int(ceil($0)) }
                    let warn = (secs ?? 99) <= 5
                    ZStack {
                        Circle().fill(Color.black.opacity(0.53)).frame(width: size, height: size)
                        Circle().stroke(Color.white.opacity(0.27), lineWidth: 3).frame(width: size + 5, height: size + 5)
                        Circle().trim(from: 0, to: frac)
                            .stroke(warn ? Color(red: 0.9, green: 0.33, blue: 0.24) : Palette.gold, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .frame(width: size + 5, height: size + 5)
                        Text(verbatim: secs.map { "\($0)" } ?? "⏱")
                            .font(.system(size: size * 0.42, weight: .bold))
                            .foregroundColor(warn ? Color(red: 1, green: 0.76, blue: 0.72) : .white)
                    }
                    .onChange(of: secs ?? -1) { s in
                        if s == 5, seat == v.mySeat, let d = deadline, warnedFor != d { warnedFor = d; Announcer.announce("باقي ٥ ثواني") }
                    }
                }
                .accessibilityHidden(true)
            }
        }
        .frame(width: size + 8, height: size + 8)
    }
}
