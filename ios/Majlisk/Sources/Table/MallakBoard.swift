import SwiftUI

// ═════════════ ملّاك: لوحة ثلاثية الأبعاد (رسم خفيف بدون محرك) + أزرار وقوائم لقارئ الشاشة ═════════════

// ───── رياضيات الثلاثي الأبعاد ─────

private struct V3 {
    var x: CGFloat, y: CGFloat, z: CGFloat
    static func + (a: V3, b: V3) -> V3 { V3(x: a.x + b.x, y: a.y + b.y, z: a.z + b.z) }
    static func - (a: V3, b: V3) -> V3 { V3(x: a.x - b.x, y: a.y - b.y, z: a.z - b.z) }
    static func * (a: V3, k: CGFloat) -> V3 { V3(x: a.x * k, y: a.y * k, z: a.z * k) }
    func dot(_ o: V3) -> CGFloat { x * o.x + y * o.y + z * o.z }
    func cross(_ o: V3) -> V3 { V3(x: y * o.z - z * o.y, y: z * o.x - x * o.z, z: x * o.y - y * o.x) }
    var norm: V3 { let l = sqrt(dot(self)); return l == 0 ? self : self * (1 / l) }
}

/// نقطة على سطح اللوحة: (u أفقي، v للأمام)، y ارتفاع
private func bp(_ u: CGFloat, _ v: CGFloat, _ y: CGFloat = 0) -> V3 { V3(x: u, y: y, z: v) }

/// الكاميرا تدور حول وسط اللوحة: yaw حول المحور العمودي، وpitch زاوية النظر من فوق
private struct Cam {
    let eye: V3, f: V3, r: V3, u: V3, focal: CGFloat, c: CGPoint
    init(yaw: CGFloat, pitch: CGFloat, size: CGSize) {
        let dist: CGFloat = 19
        eye = V3(x: dist * cos(pitch) * sin(yaw), y: dist * sin(pitch), z: dist * cos(pitch) * cos(yaw))
        f = (V3(x: 0, y: 0, z: 0) - eye).norm
        r = f.cross(V3(x: 0, y: 1, z: 0)).norm
        u = r.cross(f)
        focal = min(size.width, size.height) * 0.98
        c = CGPoint(x: size.width / 2, y: size.height * 0.4)
    }
    func depth(_ p: V3) -> CGFloat { (p - eye).dot(f) }
    func scale(_ p: V3) -> CGFloat { focal / max(0.5, depth(p)) }
    func project(_ p: V3) -> CGPoint {
        let d = p - eye
        let z = max(0.5, d.dot(f))
        return CGPoint(x: c.x + d.dot(r) / z * focal, y: c.y - d.dot(u) / z * focal)
    }
    func facing(_ center: V3, _ normal: V3) -> Bool { normal.dot(eye - center) > 0 }
}

/// حدود الخانة على اللوحة (u0..u1، v0..v1) والجهة: 0 تحت، 1 يسار، 2 فوق، 3 يمين، -1 زاوية
private struct Cell {
    var u0: CGFloat, u1: CGFloat, v0: CGFloat, v1: CGFloat, side: Int
    var cu: CGFloat { (u0 + u1) / 2 }
    var cv: CGFloat { (v0 + v1) / 2 }
}

private func cell(_ i: Int) -> Cell {
    switch i {
    case 0: return Cell(u0: 4.5, u1: 6.5, v0: 4.5, v1: 6.5, side: -1)
    case 1..<10: let c = 5 - CGFloat(i); return Cell(u0: c - 0.5, u1: c + 0.5, v0: 4.5, v1: 6.5, side: 0)
    case 10: return Cell(u0: -6.5, u1: -4.5, v0: 4.5, v1: 6.5, side: -1)
    case 11..<20: let c = 5 - CGFloat(i - 10); return Cell(u0: -6.5, u1: -4.5, v0: c - 0.5, v1: c + 0.5, side: 1)
    case 20: return Cell(u0: -6.5, u1: -4.5, v0: -6.5, v1: -4.5, side: -1)
    case 21..<30: let c = -5 + CGFloat(i - 20); return Cell(u0: c - 0.5, u1: c + 0.5, v0: -6.5, v1: -4.5, side: 2)
    case 30: return Cell(u0: 4.5, u1: 6.5, v0: -6.5, v1: -4.5, side: -1)
    default: let c = -5 + CGFloat(i - 30); return Cell(u0: 4.5, u1: 6.5, v0: c - 0.5, v1: c + 0.5, side: 3)
    }
}

/// شريط لون المجموعة (على الحافة الداخلية للخانة)
private func band(_ c: Cell) -> Cell {
    var b = c
    switch c.side { case 0: b.v1 = c.v0 + 0.45; case 1: b.u0 = c.u1 - 0.45; case 2: b.v0 = c.v1 - 0.45; case 3: b.u1 = c.u0 + 0.45; default: break }
    return b
}

/// علامة المالك (على الحافة الخارجية)
private func ownerStrip(_ c: Cell) -> Cell {
    var b = c
    switch c.side { case 0: b.v0 = c.v1 - 0.18; case 1: b.u1 = c.u0 + 0.18; case 2: b.v1 = c.v0 + 0.18; case 3: b.u0 = c.u1 - 0.18; default: break }
    return b
}

/// مكان الحجر في الخانة (بعيد عن شريط اللون)، وكل لاعب له مكان صغير
private func pawnSpot(_ i: Int, _ slot: Int) -> (CGFloat, CGFloat) {
    let c = cell(i)
    let (bu, bv): (CGFloat, CGFloat) = c.side == 0 ? (0, 0.25) : c.side == 1 ? (-0.25, 0) : c.side == 2 ? (0, -0.25) : c.side == 3 ? (0.25, 0) : (0, 0.4)
    let span: CGFloat = c.side < 0 ? 0.42 : 0.22
    let du = CGFloat(slot % 3 - 1) * span
    let dv = (CGFloat(slot / 3) - 0.5) * span * 1.4
    return c.side == 1 || c.side == 3 ? (c.cu + bu + dv, c.cv + bv + du) : (c.cu + bu + du, c.cv + bv + dv)
}

/// مكان اسم الخانة (k=0) وسعرها (k=1): بعيد عن شريط اللون، والسعر تحت الاسم
private func textSpot(_ i: Int, _ k: Int) -> (CGFloat, CGFloat) {
    let c = cell(i)
    let (ou, ov): (CGFloat, CGFloat) = c.side == 0 ? (0, 0.22) : c.side == 1 ? (-0.22, 0) : c.side == 2 ? (0, -0.22) : (0.22, 0)
    let u = c.cu + ou, v = c.cv + ov
    return c.side == 1 || c.side == 3 ? (u, v + (k == 1 ? 0.24 : -0.14)) : (u, v + (k == 1 ? 0.38 : -0.2))
}

private func polygon(_ cam: Cam, _ pts: [V3]) -> Path {
    var p = Path()
    for (k, q) in pts.enumerated() { let s = cam.project(q); if k == 0 { p.move(to: s) } else { p.addLine(to: s) } }
    p.closeSubpath()
    return p
}

private func quadPath(_ cam: Cam, _ c: Cell, _ y: CGFloat) -> Path {
    polygon(cam, [bp(c.u0, c.v0, y), bp(c.u1, c.v0, y), bp(c.u1, c.v1, y), bp(c.u0, c.v1, y)])
}

private extension Color {
    /// نفس اللون أغمق أو أفتح (k أقل من 1 = أغمق)
    func shade(_ k: CGFloat) -> Color {
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        if k <= 1 { return Color(red: r * k, green: g * k, blue: b * k, opacity: a) }
        let t = k - 1
        return Color(red: r + (1 - r) * t, green: g + (1 - g) * t, blue: b + (1 - b) * t, opacity: a)
    }
}

/// صندوق ثلاثي (بيت أو برج): الوجوه المواجهة للكاميرا بس، مع إضاءة بسيطة
private func drawBox(_ ctx: GraphicsContext, _ cam: Cam, u: CGFloat, v: CGFloat, w: CGFloat, h: CGFloat, d: CGFloat, color: Color) {
    let x0 = u - w / 2, x1 = u + w / 2, z0 = v - d / 2, z1 = v + d / 2
    let faces: [([V3], V3, CGFloat)] = [
        ([V3(x: x0, y: h, z: z0), V3(x: x1, y: h, z: z0), V3(x: x1, y: h, z: z1), V3(x: x0, y: h, z: z1)], V3(x: 0, y: 1, z: 0), 1),
        ([V3(x: x0, y: 0, z: z1), V3(x: x1, y: 0, z: z1), V3(x: x1, y: h, z: z1), V3(x: x0, y: h, z: z1)], V3(x: 0, y: 0, z: 1), 0.8),
        ([V3(x: x0, y: 0, z: z0), V3(x: x1, y: 0, z: z0), V3(x: x1, y: h, z: z0), V3(x: x0, y: h, z: z0)], V3(x: 0, y: 0, z: -1), 0.65),
        ([V3(x: x1, y: 0, z: z0), V3(x: x1, y: 0, z: z1), V3(x: x1, y: h, z: z1), V3(x: x1, y: h, z: z0)], V3(x: 1, y: 0, z: 0), 0.72),
        ([V3(x: x0, y: 0, z: z0), V3(x: x0, y: 0, z: z1), V3(x: x0, y: h, z: z1), V3(x: x0, y: h, z: z0)], V3(x: -1, y: 0, z: 0), 0.72),
    ]
    for (pts, n, k) in faces {
        let center = pts.reduce(V3(x: 0, y: 0, z: 0), +) * 0.25
        guard cam.facing(center, n) else { continue }
        let path = polygon(cam, pts)
        ctx.fill(path, with: .color(color.shade(k)))
        ctx.stroke(path, with: .color(.black.opacity(0.25)), lineWidth: 1)
    }
}

/// حجر اللاعب: ظل وقاعدة ورأس كروي بلمعة (حجمه حسب بعده عن الكاميرا)
private func drawPawn(_ ctx: GraphicsContext, _ cam: Cam, u: CGFloat, v: CGFloat, lift: CGFloat, color: Color) {
    let base = cam.project(bp(u, v, 0))
    let s = cam.scale(bp(u, v, 0)) * 0.2
    ctx.fill(Path(ellipseIn: CGRect(x: base.x - s, y: base.y - s * 0.35, width: s * 2, height: s * 0.7)), with: .color(.black.opacity(0.35 * (1 - lift * 0.4))))
    let top = cam.project(bp(u, v, 0.35 + lift * 0.6))
    let b = cam.project(bp(u, v, lift * 0.6))
    var body = Path()
    body.move(to: CGPoint(x: b.x - s * 0.8, y: b.y)); body.addLine(to: CGPoint(x: b.x + s * 0.8, y: b.y))
    body.addLine(to: CGPoint(x: top.x + s * 0.35, y: top.y + s * 0.4)); body.addLine(to: CGPoint(x: top.x - s * 0.35, y: top.y + s * 0.4)); body.closeSubpath()
    ctx.fill(body, with: .linearGradient(Gradient(colors: [color.shade(1.6), color, color.shade(0.5)]), startPoint: CGPoint(x: top.x - s, y: top.y), endPoint: CGPoint(x: top.x + s, y: top.y)))
    let head = CGRect(x: top.x - s * 0.62, y: top.y - s * 0.62, width: s * 1.24, height: s * 1.24)
    ctx.fill(Path(ellipseIn: head), with: .radialGradient(Gradient(colors: [color.shade(1.6), color, color.shade(0.5)]), center: CGPoint(x: top.x - s * 0.25, y: top.y - s * 0.3), startRadius: 0, endRadius: s * 0.9))
    ctx.fill(Path(ellipseIn: CGRect(x: top.x - s * 0.36, y: top.y - s * 0.39, width: s * 0.28, height: s * 0.28)), with: .color(.white.opacity(0.7)))
}

// ───── النرد الثلاثي ─────

private func rotX(_ p: V3, _ a: CGFloat) -> V3 { V3(x: p.x, y: p.y * cos(a) - p.z * sin(a), z: p.y * sin(a) + p.z * cos(a)) }
private func rotY(_ p: V3, _ a: CGFloat) -> V3 { V3(x: p.x * cos(a) + p.z * sin(a), y: p.y, z: -p.x * sin(a) + p.z * cos(a)) }
private func rotZ(_ p: V3, _ a: CGFloat) -> V3 { V3(x: p.x * cos(a) - p.y * sin(a), y: p.x * sin(a) + p.y * cos(a), z: p.z) }
/// الوجه اللي فوق لكل رقم: 1 فوق، 6 تحت، 2 قدام، 5 ورا، 3 يمين، 4 يسار
private func faceUp(_ p: V3, _ value: Int) -> V3 {
    switch value {
    case 6: return rotX(p, .pi)
    case 2: return rotX(p, -.pi / 2)
    case 5: return rotX(p, .pi / 2)
    case 3: return rotZ(p, .pi / 2)
    case 4: return rotZ(p, -.pi / 2)
    default: return p
    }
}
private let PIPS: [Int: [(CGFloat, CGFloat)]] = [
    1: [(0, 0)], 2: [(-1, -1), (1, 1)], 3: [(-1, -1), (0, 0), (1, 1)], 4: [(-1, -1), (1, -1), (-1, 1), (1, 1)],
    5: [(-1, -1), (1, -1), (0, 0), (-1, 1), (1, 1)], 6: [(-1, -1), (1, -1), (-1, 0), (1, 0), (-1, 1), (1, 1)],
]

private func drawDie(_ ctx: GraphicsContext, _ cam: Cam, cx: CGFloat, cz: CGFloat, value: Int, spin: CGFloat, yaw: CGFloat) {
    let h: CGFloat = 0.45
    let faces: [(Int, V3, V3, V3)] = [
        (1, V3(x: 0, y: 1, z: 0), V3(x: 1, y: 0, z: 0), V3(x: 0, y: 0, z: 1)),
        (6, V3(x: 0, y: -1, z: 0), V3(x: 1, y: 0, z: 0), V3(x: 0, y: 0, z: 1)),
        (2, V3(x: 0, y: 0, z: 1), V3(x: 1, y: 0, z: 0), V3(x: 0, y: 1, z: 0)),
        (5, V3(x: 0, y: 0, z: -1), V3(x: 1, y: 0, z: 0), V3(x: 0, y: 1, z: 0)),
        (3, V3(x: 1, y: 0, z: 0), V3(x: 0, y: 0, z: 1), V3(x: 0, y: 1, z: 0)),
        (4, V3(x: -1, y: 0, z: 0), V3(x: 0, y: 0, z: 1), V3(x: 0, y: 1, z: 0)),
    ]
    let center = V3(x: cx, y: h + 0.05 + spin * 0.8, z: cz)
    let rot = { (p: V3) -> V3 in rotY(rotX(faceUp(p, value), spin * 9), yaw + spin * 7) }
    let tf = { (p: V3) -> V3 in center + rot(p) }
    let visible = faces.filter { cam.facing(tf($0.1 * h), rot($0.1)) }.sorted { cam.depth(tf($0.1 * h)) > cam.depth(tf($1.1 * h)) }
    for (n, normal, a, b) in visible {
        let quad: [(CGFloat, CGFloat)] = [(-1, -1), (1, -1), (1, 1), (-1, 1)]
        let corners = quad.map { q in tf(normal * h + a * (q.0 * h) + b * (q.1 * h)) }
        let path = polygon(cam, corners)
        let light = 0.75 + 0.25 * max(0, rot(normal).y)
        ctx.fill(path, with: .color(Color(red: 0.97 * light, green: 0.95 * light, blue: 0.91 * light)))
        ctx.stroke(path, with: .color(.black.opacity(0.33)), lineWidth: 1.2)
        for (x, y) in PIPS[n] ?? [] {
            let p = tf(normal * (h * 1.001) + a * (x * h * 0.5) + b * (y * h * 0.5))
            let s = cam.project(p), r = cam.scale(p) * h * 0.13
            ctx.fill(Path(ellipseIn: CGRect(x: s.x - r, y: s.y - r, width: r * 2, height: r * 2)), with: .color(Color(white: 0.1)))
        }
    }
}

// ───── رسم اللوحة كاملة ─────

struct MallakHop { let seat: Int; let path: [Int]; let startAt: Double; let step: Double
    var end: Double { startAt + step * Double(max(1, path.count - 1)) }
}

private func drawLabel(_ ctx: GraphicsContext, _ cam: Cam, u: CGFloat, v: CGFloat, text: String, worldSize: CGFloat, color: Color, bold: Bool = false, maxWidth: CGFloat = .greatestFiniteMagnitude) {
    let p = bp(u, v, 0.02)
    var px = cam.scale(p) * worldSize
    guard px >= 7 else { return }
    // تقدير عرض النص (عربي): أعرض من الخانة = سطرين (عند المسافة اللي تعطي أقصر سطر)، وإلا نصغّره
    let est = { (s: String) in CGFloat(s.count) * px * 0.52 }
    var lines = [text]
    var w = est(text)
    if w > maxWidth && text.contains(" ") {
        let words = text.split(separator: " ").map(String.init)
        let best = (1..<words.count).map { k in [words[..<k].joined(separator: " "), words[k...].joined(separator: " ")] }
            .min { max(est($0[0]), est($0[1])) < max(est($1[0]), est($1[1])) }!
        lines = best; w = max(est(best[0]), est(best[1]))
    }
    if w > maxWidth { px *= maxWidth / w; if px < 6 { return } }
    let s = cam.project(p)
    for (k, line) in lines.enumerated() {
        let t = ctx.resolve(Text(line).font(.system(size: px, weight: bold ? .bold : .medium)).foregroundColor(color))
        ctx.draw(t, at: CGPoint(x: s.x, y: s.y + (CGFloat(k) - CGFloat(lines.count - 1) / 2) * px * 1.05))
    }
}

private func drawMallak(_ ctx: GraphicsContext, size: CGSize, m: MallakView, yaw: CGFloat, pitch: CGFloat, hops: [Int: MallakHop], now: Double, spin: CGFloat) {
    let cam = Cam(yaw: yaw, pitch: pitch, size: size)
    // جوانب اللوحة (خشب) ثم السطح
    let hgt: CGFloat = -0.45
    let sides: [([V3], V3)] = [
        ([bp(-6.7, 6.7), bp(6.7, 6.7), bp(6.7, 6.7, hgt), bp(-6.7, 6.7, hgt)], V3(x: 0, y: 0, z: 1)),
        ([bp(-6.7, -6.7), bp(6.7, -6.7), bp(6.7, -6.7, hgt), bp(-6.7, -6.7, hgt)], V3(x: 0, y: 0, z: -1)),
        ([bp(6.7, -6.7), bp(6.7, 6.7), bp(6.7, 6.7, hgt), bp(6.7, -6.7, hgt)], V3(x: 1, y: 0, z: 0)),
        ([bp(-6.7, -6.7), bp(-6.7, 6.7), bp(-6.7, 6.7, hgt), bp(-6.7, -6.7, hgt)], V3(x: -1, y: 0, z: 0)),
    ]
    for (pts, n) in sides {
        let center = pts.reduce(V3(x: 0, y: 0, z: 0), +) * 0.25
        if cam.facing(center, n) { ctx.fill(polygon(cam, pts), with: .color(Color(red: 0.24, green: 0.16, blue: 0.09))) }
    }
    ctx.fill(quadPath(cam, Cell(u0: -6.7, u1: 6.7, v0: -6.7, v1: 6.7, side: -1), 0), with: .color(Color(red: 0.42, green: 0.29, blue: 0.17)))
    ctx.fill(quadPath(cam, Cell(u0: -6.5, u1: 6.5, v0: -6.5, v1: 6.5, side: -1), 0.001), with: .color(Color(red: 0.91, green: 0.95, blue: 0.89)))
    ctx.fill(quadPath(cam, Cell(u0: -4.5, u1: 4.5, v0: -4.5, v1: 4.5, side: -1), 0.002), with: .color(Color(red: 0.12, green: 0.37, blue: 0.26)))
    drawLabel(ctx, cam, u: 0, v: -1.6, text: tr("تاجر العقار"), worldSize: 0.8, color: Color(red: 0.96, green: 0.84, blue: 0.48), bold: true)
    for i in 0..<40 {
        let c = cell(i)
        let sq = MALLAK_BOARD[i]
        ctx.fill(quadPath(cam, c, 0.003), with: .color(c.side < 0 ? Color(red: 0.95, green: 0.93, blue: 0.85) : Color(red: 0.98, green: 0.97, blue: 0.93)))
        let o = i < m.owner.count ? m.owner[i] : nil
        if sq.kind == "city" { ctx.fill(quadPath(cam, band(c), 0.004), with: .color(MALLAK_GROUP_COLORS[sq.group])) }
        if let o { ctx.fill(quadPath(cam, ownerStrip(c), 0.004), with: .color(MALLAK_PLAYER_COLORS[o % 6])) }
        if i < m.mortgaged.count && m.mortgaged[i] { ctx.fill(quadPath(cam, c, 0.005), with: .color(Color.gray.opacity(0.55))) }
        ctx.stroke(quadPath(cam, c, 0.006), with: .color(Color(red: 0.12, green: 0.19, blue: 0.12).opacity(0.33)), lineWidth: 1)
        let (lu, lv): (CGFloat, CGFloat) = c.side < 0 ? (c.cu, c.cv - 0.45) : textSpot(i, 0)
        let width = cam.scale(bp(c.cu, c.cv)) * (c.side < 0 ? 1.9 : c.side == 1 || c.side == 3 ? 1.45 : 0.92)
        let icon: String = ["chance": "؟ ", "chest": "📦 ", "station": "✈ ", "utility": "⚡ ", "tax": "💰 ", "jail": "🔒 ", "goToJail": "👮 ", "rest": "☕ ", "go": "➜ "][sq.kind] ?? ""
        drawLabel(ctx, cam, u: lu, v: lv, text: icon + tr(sq.name), worldSize: c.side < 0 ? 0.3 : 0.2, color: Color(red: 0.11, green: 0.17, blue: 0.13), bold: c.side < 0, maxWidth: width)
        if sq.price > 0 && o == nil {
            let (pu, pv): (CGFloat, CGFloat) = c.side < 0 ? (c.cu, c.cv + 0.3) : textSpot(i, 1)
            drawLabel(ctx, cam, u: pu, v: pv, text: "\(sq.price)", worldSize: 0.17, color: Color(red: 0.33, green: 0.38, blue: 0.35), maxWidth: width)
        }
    }
    // البيوت والأبراج على شريط اللون
    for i in 0..<min(40, m.houses.count) where m.houses[i] > 0 {
        let n = m.houses[i]
        let b = band(cell(i))
        if n == 5 { drawBox(ctx, cam, u: b.cu, v: b.cv, w: 0.38, h: 0.55, d: 0.32, color: Color(red: 0.78, green: 0.16, blue: 0.16)); continue }
        for k in 0..<n {
            let t = (CGFloat(k) - CGFloat(n - 1) / 2) * 0.22
            let side = cell(i).side
            let (u, v) = side == 1 || side == 3 ? (b.cu, b.cv + t) : (b.cu + t, b.cv)
            drawBox(ctx, cam, u: u, v: v, w: 0.17, h: 0.2, d: 0.17, color: Color(red: 0.18, green: 0.49, blue: 0.2))
        }
    }
    // الأحجار (الأبعد أول)
    var pawns: [(Int, CGFloat, CGFloat, CGFloat, CGFloat)] = []
    for seat in m.seats where seat < m.players.count && m.players[seat]?.bankrupt == false {
        let p = m.players[seat]!
        let slot = m.seats.firstIndex(of: seat) ?? 0
        var lift: CGFloat = 0
        var pos = pawnSpot(p.pos, slot)
        if let hop = hops[seat], now < hop.end, hop.path.count > 1 {
            let t = min(max(0, (now - hop.startAt) / hop.step), Double(hop.path.count - 1))
            let k = min(Int(t), hop.path.count - 2)
            let f = CGFloat(t - Double(k))
            if t > 0 { lift = sin(.pi * f) * 0.6 }
            let a = pawnSpot(hop.path[k], slot), b = pawnSpot(hop.path[k + 1], slot)
            pos = (a.0 + (b.0 - a.0) * f, a.1 + (b.1 - a.1) * f)
        }
        pawns.append((seat, pos.0, pos.1, lift, cam.depth(bp(pos.0, pos.1))))
    }
    for (seat, u, v, lift, _) in pawns.sorted(by: { $0.4 > $1.4 }) { drawPawn(ctx, cam, u: u, v: v, lift: lift, color: MALLAK_PLAYER_COLORS[seat % 6]) }
    // النرد في الوسط
    if let d = m.dice {
        drawDie(ctx, cam, cx: -0.75, cz: 0.9, value: d.0, spin: spin, yaw: 0.35)
        drawDie(ctx, cam, cx: 0.75, cz: 0.9, value: d.1, spin: spin * 0.9, yaw: -0.3)
    }
}

/// أي خانة تحت اللمسة
private func hitSquare(_ at: CGPoint, size: CGSize, yaw: CGFloat, pitch: CGFloat) -> Int? {
    let cam = Cam(yaw: yaw, pitch: pitch, size: size)
    for i in 0..<40 where quadPath(cam, cell(i), 0).contains(at) { return i }
    return nil
}

// ───── الشاشة ─────

struct MallakBoard: View {
    let v: TableView
    let m: MallakView
    @ObservedObject var conn: TableConnection
    let isOwner: Bool
    @Environment(\.accessibilityVoiceOverEnabled) private var reader
    @State private var yaw: CGFloat = 0
    @State private var pitch: CGFloat = 0.98
    @State private var dragStart: (CGFloat, CGFloat)?
    @State private var hops: [Int: MallakHop] = [:]
    @State private var seenMove = -1
    @State private var seenRoll = -1
    @State private var rollAt: Double = 0
    @State private var info: Int?
    @State private var listOpen = false
    @State private var logOpen = false
    @State private var manageOpen = false
    @State private var tradeOpen = false
    /// يتغير لما تخلص الحركة: يوقف تحديث الرسم المستمر
    @State private var animTick = 0

    private var names: [String] { (0..<max(6, v.seats.count)).map { v.seat($0)?.username ?? "المقعد \($0 + 1)" } }
    private var me: MallakPlayerUi? { v.mySeat.flatMap { s in m.playersUi.first { $0.seat == s } } }

    private func act(_ type: String, _ extra: JSON = [:]) {
        var a = extra; a["type"] = type
        conn.send(["type": "mallak", "action": a])
    }

    /// حالة جديدة: حركة الحجر خانة خانة (نفس توقيت صوت الخطوات)، ودحرجة النرد
    private func animate() {
        let now = Date().timeIntervalSince1970
        let rolledNow = seenRoll >= 0 && m.rollSeq != seenRoll
        if rolledNow { rollAt = now }
        seenRoll = m.rollSeq
        if seenMove >= 0 && m.moveSeq != seenMove && m.moveKind != "jail" && m.moveSeat >= 0 {
            let fwd = (m.moveTo - m.moveFrom + 40) % 40
            let back = m.moveKind == "card" && fwd > 20
            let n = back ? 40 - fwd : fwd
            let path = (0...max(0, n)).map { k in (((back ? m.moveFrom - k : m.moveFrom + k) % 40) + 40) % 40 }
            let step = n > 13 ? 2.86 / Double(n) : Sounds.stepGap
            hops[m.moveSeat] = MallakHop(seat: m.moveSeat, path: path, startAt: now + (rolledNow ? 0.55 : 0), step: step)
        }
        seenMove = m.moveSeq
    }

    private func read(_ raw: SwipeDir) -> Bool {
        let cur = conn.view?.mallak ?? m
        let dir: SwipeDir = raw == .up ? .down : raw == .down ? .up : raw
        switch dir {
        case .up: Announcer.announceNow("\(cur.turnText). \(cur.hereText)")
        case .down: listOpen = true
        case .left: Announcer.announceNow(me?.text ?? cur.turnText)
        case .right:
            if cur.actions.contains(where: { $0.type == "roll" }) { act("roll") }
            else { Announcer.announceNow(cur.myTurn ? (cur.prompt.isEmpty ? cur.turnText : cur.prompt) : cur.turnText) }
        }
        return true
    }

    /// أزرار ثانية: عقاراتي، التفاوض، قائمة اللوحة، السجل
    private var moreButtons: [(String, Bool, () -> Void)] {
        var out: [(String, Bool, () -> Void)] = []
        if v.mySeat != nil && m.phase != "over" { out.append(("عقاراتي", false, { manageOpen = true })) }
        if m.canTrade { out.append(("تفاوض", false, { tradeOpen = true })) }
        out.append(("اللوحة", false, { listOpen = true }))
        out.append(("السجل", false, { logOpen = true }))
        return out
    }

    /// أزرار القرار الحين
    private var actionButtons: [(String, Bool, () -> Void)] {
        m.actions.map { a -> (String, Bool, () -> Void) in
            let primary = ["roll", "buy", "accept", "endTurn"].contains(a.type) || (a.type == "bid" && a.id == m.actions.first?.id)
            return (a.label, primary, { if a.type == "bid" { act("bid", ["amount": a.amount ?? 0]) } else { act(a.type) } })
        }
    }

    // (الواجهة مقسّمة أجزاء صغيرة: لو كانت كلها في body وحدة، مترجم Swift ما يلحق يفحصها)

    /// اللاعبون: لون الحجر والاسم والفلوس
    private var playersStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) { ForEach(m.playersUi) { p in playerChip(p) } }
        }
    }

    private func playerChip(_ p: MallakPlayerUi) -> some View {
        let turn: Bool = p.seat == m.turn && m.phase != "over"
        let name: String = names[p.seat] + (p.seat == v.mySeat ? " (أنت)" : "")
        let money: String = p.bankrupt ? "مفلس" : "\(p.cash) ريال" + (p.inJail ? " 🔒" : "")
        let label: String = "\(p.text)، \(MALLAK_PLAYER_COLOR_NAMES[p.seat % 6])" + (turn ? "، عليه الدور" : "")
        return HStack(spacing: 5) {
            Circle().fill(MALLAK_PLAYER_COLORS[p.seat % 6]).frame(width: 12, height: 12)
            VStack(alignment: .leading, spacing: 1) {
                Text(trSpoken(name)).font(.system(size: 13, weight: turn ? .bold : .regular)).foregroundColor(p.bankrupt ? Palette.textDim : Palette.text)
                Text(trSpoken(money)).font(.system(size: 12)).foregroundColor(Palette.goldSoft)
            }
            TurnClock(v: v, seat: p.seat, turn: turn)
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 12).fill(turn ? Palette.gold.opacity(0.33) : Color.black.opacity(0.2)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(turn ? Palette.gold : Color.clear, lineWidth: 2))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(trSpoken(label))
    }

    /// الحالة: الدور، ونص قرارك، والمزاد/التفاوض/البطاقة
    private var statusBox: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(trSpoken(m.turnText)).bold().foregroundColor(Palette.goldSoft).accessibilityAddTraits(.isHeader)
            if m.myTurn && !m.prompt.isEmpty { Text(trSpoken(m.prompt)).font(.system(size: 14)) }
            if !m.auctionText.isEmpty { Text(trSpoken(m.auctionText)).font(.system(size: 14)) }
            if !m.tradeText.isEmpty { Text(trSpoken(m.tradeText)).font(.system(size: 14)) }
            if !m.cardText.isEmpty && m.phase != "over" { Text(trSpoken("🃏 " + m.cardText)).font(.system(size: 13)).foregroundColor(Palette.textDim) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8).background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.2)))
    }

    /// الرسم نفسه (يتحدث مع كل إطار وقت الحركة)
    private func canvas(_ animating: Bool) -> some View {
        TimelineView(.animation(paused: !animating)) { tl in
            let t: Double = tl.date.timeIntervalSince1970
            let k: Double = max(0, min(1, (0.7 - (t - rollAt)) / 0.7))
            let spin = CGFloat(k * k)
            Canvas { ctx, size in drawMallak(ctx, size: size, m: m, yaw: yaw, pitch: pitch, hops: hops, now: t, spin: spin) }
        }
    }

    private func onDrag(_ g: DragGesture.Value) {
        guard !reader else { return }
        if dragStart == nil { dragStart = (yaw, pitch) }
        let start = dragStart!
        yaw = start.0 + g.translation.width * 0.008
        pitch = min(1.45, max(0.55, start.1 - g.translation.height * 0.005))
    }

    private func onDragEnd(_ g: DragGesture.Value, _ size: CGSize) {
        defer { dragStart = nil }
        guard !reader else { return }
        if abs(g.translation.width) < 6 && abs(g.translation.height) < 6 {
            if let start = dragStart { yaw = start.0; pitch = start.1 }
            info = hitSquare(g.location, size: size, yaw: yaw, pitch: pitch)
        }
    }

    /// اللوحة: للعين (اللمس يقرأ الخانة، والسحب يدوّر اللوحة)، وقارئ الشاشة يستخدم القائمة والإيماءات
    private func board(_ animating: Bool) -> some View {
        let lastEnd: Double = hops.values.map(\.end).max() ?? 0
        return canvas(animating)
            .task(id: lastEnd + rollAt) {
                let end = max(lastEnd, rollAt + 0.7)
                let wait = end - Date().timeIntervalSince1970 + 0.05
                if wait > 0 { try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000)) }
                if Task.isCancelled { return }
                let n = Date().timeIntervalSince1970
                hops = hops.filter { $0.value.end > n }
                animTick &+= 1
            }
            .aspectRatio(1, contentMode: .fit).frame(maxWidth: 560)
            .overlay(GeometryReader { geo in
                Color.clear.contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onChanged { onDrag($0) }.onEnded { onDragEnd($0, geo.size) })
                    .onTapGesture(count: 2) { if !reader { yaw = 0; pitch = 0.98 } }
            })
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
    }

    @ViewBuilder private var endBox: some View {
        if m.phase == "over" {
            let w = m.winner ?? 0
            Text(trSpoken(m.winner == v.mySeat ? "🎉 فزت!" : "فاز " + names[w])).font(.system(size: 20, weight: .bold)).foregroundColor(Palette.goldSoft)
            if isOwner { MButton("لعبة جديدة", .primary) { conn.send("start") } }
        }
    }

    private var content: some View {
        let now = Date().timeIntervalSince1970
        let animating: Bool = !hops.isEmpty || now - rollAt < 0.7
        return VStack(spacing: 8) {
            playersStrip
            statusBox
            board(animating)
            if !m.actions.isEmpty { FlowButtons(items: actionButtons) }
            FlowButtons(items: moreButtons)
            endBox
        }
        .foregroundColor(Palette.text)
    }

    private var squareSheetItem: Binding<MallakSheetItem?> {
        Binding(get: { info.map { MallakSheetItem(id: $0) } }, set: { info = $0?.id })
    }

    private func squareSheet(_ item: MallakSheetItem) -> some View {
        Sheet(title: MALLAK_BOARD[item.id].name) {
            Text(trSpoken(item.id < m.squares.count ? m.squares[item.id] : ""))
            MButton("إغلاق") { info = nil }
        }
    }

    private var listSheet: some View {
        let cur = conn.view?.mallak ?? m
        return Sheet(title: "خانات اللوحة") {
            ForEach(Array(cur.squares.enumerated()), id: \.offset) { _, s in Text(trSpoken(s)).frame(maxWidth: .infinity, alignment: .leading) }
            MButton("إغلاق") { listOpen = false }
        }
    }

    private var logSheet: some View {
        let cur = conn.view?.mallak ?? m
        let lines: [String] = Array(cur.log.suffix(80).reversed())
        return Sheet(title: "سجل اللعبة") {
            if lines.isEmpty { Note("ما فيه شي بعد") }
            ForEach(Array(lines.enumerated()), id: \.offset) { _, s in Text(trSpoken(s)).frame(maxWidth: .infinity, alignment: .leading) }
            MButton("إغلاق") { logOpen = false }
        }
    }

    @ViewBuilder private var tradeSheet: some View {
        if let s = v.mySeat {
            MallakTradeSheet(m: conn.view?.mallak ?? m, me: s, names: names, send: { act("propose", ["offer": $0]) }, close: { tradeOpen = false })
        }
    }

    var body: some View {
        let _ = animTick
        content
            .onAppear { seenMove = m.moveSeq; seenRoll = m.rollSeq; Gestures.shared.set("mallak") { read($0) } }
            .onDisappear { Gestures.shared.clear("mallak") }
            .onChange(of: m.moveSeq) { _ in animate() }
            .onChange(of: m.rollSeq) { _ in animate() }
            .sheet(item: squareSheetItem) { squareSheet($0) }
            .sheet(isPresented: $listOpen) { listSheet }
            .sheet(isPresented: $logOpen) { logSheet }
            .sheet(isPresented: $manageOpen) { MallakManageSheet(conn: conn, close: { manageOpen = false }) }
            .sheet(isPresented: $tradeOpen) { tradeSheet }
    }
}

private struct MallakSheetItem: Identifiable { let id: Int }

/// صف أزرار يلتف لسطر ثاني لو ما وسعها السطر
private struct FlowButtons: View {
    let items: [(String, Bool, () -> Void)]
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 6)], spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, it in SmallButton(it.0, primary: it.1, action: it.2) }
        }
    }
}

/// عقاراتي: بناء وبيع ورهن وفك رهن (تتحدث مع كل حالة)
private struct MallakManageSheet: View {
    @ObservedObject var conn: TableConnection
    let close: () -> Void
    private func act(_ type: String, _ sq: Int) { conn.send(["type": "mallak", "action": ["type": type, "square": sq]]) }
    var body: some View {
        let m = conn.view?.mallak
        Sheet(title: "عقاراتي") {
            if let me = conn.view?.mySeat, let p = m?.playersUi.first(where: { $0.seat == me }) { Note("معك \(p.cash) ريال") }
            if m?.myProps.isEmpty ?? true { Note("ما تملك عقارات") }
            ForEach(m?.myProps ?? []) { p in
                Text(trSpoken("\(p.name)\(p.houses == 5 ? "، برج" : p.houses > 0 ? "، \(p.houses) بيوت" : "")\(p.mortgaged ? "، مرهون" : "")"))
                    .bold().foregroundColor(Palette.goldSoft).accessibilityAddTraits(.isHeader)
                HStack(spacing: 6) {
                    if p.build { SmallButton(p.houses == 4 ? "ابنِ برج" : "ابنِ بيت", primary: true, label: "ابنِ في \(p.name)") { act("build", p.square) } }
                    if p.sell { SmallButton("بِع بيت", label: "بِع بيت في \(p.name)") { act("sell", p.square) } }
                    if p.mortgage { SmallButton("ارهن", label: "ارهن \(p.name)") { act("mortgage", p.square) } }
                    if p.unmortgage { SmallButton("فك الرهن", label: "فك رهن \(p.name)") { act("unmortgage", p.square) } }
                }
            }
            MButton("إغلاق", action: close)
        }
    }
}

/// التفاوض: تختار اللاعب، وش تعطيه (عقارات وفلوس)، ووش تبي منه
private struct MallakTradeSheet: View {
    let m: MallakView
    let me: Int
    let names: [String]
    let send: (JSON) -> Void
    let close: () -> Void
    @State private var to: Int?
    @State private var give: Set<Int> = []
    @State private var get: Set<Int> = []
    @State private var giveCash = ""
    @State private var getCash = ""

    /// مجموعة فيها بيوت: ما تنتبادل (لازم تنباع البيوت أول)
    private func tradable(_ i: Int) -> Bool {
        let sq = MALLAK_BOARD[i]
        guard sq.kind == "city" else { return true }
        return !(0..<40).contains { j in MALLAK_BOARD[j].kind == "city" && MALLAK_BOARD[j].group == sq.group && j < m.houses.count && m.houses[j] > 0 }
    }
    private func owned(by s: Int) -> [Int] { (0..<40).filter { $0 < m.owner.count && m.owner[$0] == s && tradable($0) } }

    var body: some View {
        let others = m.alive.filter { $0 != me }
        let target = to ?? others.first
        Sheet(title: "تفاوض") {
            Text(trSpoken("مع مين؟")).bold().foregroundColor(Palette.goldSoft).accessibilityAddTraits(.isHeader)
            HStack(spacing: 6) {
                ForEach(others, id: \.self) { s in SmallButton(names[s], primary: target == s, label: "\(names[s])\(target == s ? "، محدد" : "")") { to = s; get = [] } }
            }
            Text(trSpoken("تعطيه")).bold().foregroundColor(Palette.goldSoft).accessibilityAddTraits(.isHeader)
            ForEach(owned(by: me), id: \.self) { i in
                SwitchRow(label: MALLAK_BOARD[i].name + (i < m.mortgaged.count && m.mortgaged[i] ? " (مرهون)" : ""), isOn: give.contains(i)) { on in if on { give.insert(i) } else { give.remove(i) } }
            }
            Field(label: "فلوس تعطيه", text: $giveCash, digits: 6)
            if let t = target {
                Text(trSpoken("تبي منه")).bold().foregroundColor(Palette.goldSoft).accessibilityAddTraits(.isHeader)
                ForEach(owned(by: t), id: \.self) { i in
                    SwitchRow(label: MALLAK_BOARD[i].name + (i < m.mortgaged.count && m.mortgaged[i] ? " (مرهون)" : ""), isOn: get.contains(i)) { on in if on { get.insert(i) } else { get.remove(i) } }
                }
                Field(label: "فلوس تبيها منه", text: $getCash, digits: 6)
            }
            let gc = Int(giveCash.filter(\.isNumber)) ?? 0, tc = Int(getCash.filter(\.isNumber)) ?? 0
            MButton("أرسل العرض", .primary, enabled: target != nil && (!give.isEmpty || !get.isEmpty || gc > 0 || tc > 0)) {
                guard let t = target else { return }
                send(["to": t, "give": Array(give), "get": Array(get), "giveCash": gc, "getCash": tc, "giveCards": 0, "getCards": 0])
                close()
            }
            MButton("إلغاء", action: close)
        }
    }
}

/// أصوات ملّاك ونص قرارك (حتى والتطبيق في الخلفية)
final class MallakSounds {
    private var prev: MallakView?
    private var wasMyTurn = false
    private var lastPrompt: String?

    func update(_ v: TableView) {
        guard let m = v.mallak else { prev = nil; wasMyTurn = false; lastPrompt = nil; return }
        let s = Sounds.shared
        if let p = prev {
            let rolled = m.rollSeq != p.rollSeq
            if rolled { s.dice() }
            if m.moveSeq != p.moveSeq {
                if m.moveKind == "jail" { s.jail() } else {
                    let fwd = (m.moveTo - m.moveFrom + 40) % 40
                    let n = m.moveKind == "card" && fwd > 20 ? 40 - fwd : fwd
                    s.steps(min(13, n), at: (rolled ? 0.55 : 0) + Sounds.stepGap)
                }
            }
            if m.cardSeq != p.cardSeq { s.drawCard() }
            if m.houses.reduce(0, +) > p.houses.reduce(0, +) { s.build() }
            let cashNow: [Int] = m.players.map { $0?.cash ?? -1 }
            let cashBefore: [Int] = p.players.map { $0?.cash ?? -1 }
            let cashChanged = cashNow != cashBefore
            if cashChanged || m.owner != p.owner { s.coins() }
            if m.phase == "over" && p.phase != "over", let me = v.mySeat {
                let won = m.winner == me
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { s.matchEnd(won: won) }
            }
        }
        prev = m
        if m.myTurn && !wasMyTurn { s.turn(soft: Announcer.readerOn) }
        // نص القرار (يكمّل الإعلان): مرة لكل تغيّر
        if m.myTurn && !m.prompt.isEmpty && (m.prompt != lastPrompt || !wasMyTurn) { Announcer.announce(m.prompt) }
        lastPrompt = m.myTurn ? m.prompt : nil
        wasMyTurn = m.myTurn
    }
}
