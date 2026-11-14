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
                    Text("⏱").font(.system(size: 13))
                    if let secs {
                        Text("\(secs)").font(.system(size: 13, weight: .bold)).foregroundColor(secs <= 5 ? Palette.goldSoft : Palette.text)
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
