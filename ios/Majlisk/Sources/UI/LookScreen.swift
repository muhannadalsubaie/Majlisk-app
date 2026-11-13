import SwiftUI

/// خيار واحد: مربع يبين الشكل، واسمه تحته، ويُقرأ «الاسم، مختار»
private struct Choice<Swatch: View>: View {
    let name: String
    let selected: Bool
    let pick: () -> Void
    @ViewBuilder let swatch: () -> Swatch
    var body: some View {
        Button {
            pick(); Announcer.announce("اخترت \(name)")
        } label: {
            VStack(spacing: 8) {
                swatch().frame(height: 44)
                Text(name).font(.system(size: 12, weight: .bold)).foregroundColor(selected ? Pro.goldLight : Pro.cream).multilineTextAlignment(.center)
            }
            .frame(width: 86).padding(.vertical, 10).padding(.horizontal, 4)
            .background(Pro.deep).clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(selected ? Pro.gold : Pro.goldLight.opacity(0.2), lineWidth: selected ? 2 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct LookRow<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content
    var body: some View {
        SectionTitle(title)
        ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 10) { content() } }
    }
}

/// تخصيص الشكل (الباقة الاحترافية): طاولة البلوت وورقها، والدومينو، ولوحة الجاكارو، ونرد اللودو.
/// الاختيار يتحفظ في جوالك ويطلع لك أنت بس.
struct LookScreen: View {
    let onBack: () -> Void
    @ObservedObject private var look = Look.shared
    @State private var game = "baloot"

    var body: some View {
        Screen {
            TopBar("تخصيص الشكل", onBack: onBack)
            HStack(spacing: 8) {
                ForEach([("baloot", "بلوت"), ("domino", "دومينو"), ("jackaroo", "جاكارو"), ("ludo", "لودو")], id: \.0) { id, label in
                    if game == id { GoldButton(title: label) {} } else { MButton(label) { game = id } }
                }
            }
            preview
                .frame(maxWidth: .infinity).frame(height: 170)
                .background(LinearGradient(colors: [Color(red: 0.137, green: 0.188, blue: 0.24), Pro.night], startPoint: .topLeading, endPoint: .bottomTrailing))
                .clipShape(RoundedRectangle(cornerRadius: 22))
                .accessibilityHidden(true)
            switch game {
            case "baloot":
                LookRow(title: "شكل الطاولة") {
                    ForEach(Look.shapes.indices, id: \.self) { i in
                        Choice(name: Look.shapes[i], selected: look.balootShape == i, pick: { look.balootShape = i }) {
                            Look.tableShape(i).fill(Color(red: 0.11, green: 0.46, blue: 0.34)).overlay(Look.tableShape(i).stroke(Color(red: 0.55, green: 0.35, blue: 0.17), lineWidth: 3)).frame(width: 48, height: 36)
                        }
                    }
                }
                LookRow(title: "لون الطاولة") {
                    ForEach(Look.felts.indices, id: \.self) { i in
                        Choice(name: Look.felts[i].name, selected: look.balootFelt == i, pick: { look.balootFelt = i }) {
                            RoundedRectangle(cornerRadius: 12).fill(RadialGradient(colors: Look.felts[i].colors, center: .center, startRadius: 0, endRadius: 30)).frame(width: 40, height: 40)
                        }
                    }
                }
                LookRow(title: "حافة الطاولة") {
                    ForEach(Look.rims.indices, id: \.self) { i in
                        Choice(name: Look.rims[i].name, selected: look.balootRim == i, pick: { look.balootRim = i }) {
                            Circle().fill(LinearGradient(colors: Look.rims[i].colors, startPoint: .top, endPoint: .bottom)).frame(width: 40, height: 40)
                        }
                    }
                }
                LookRow(title: "وجه الورق") {
                    ForEach(Look.faces.indices, id: \.self) { i in
                        let bg: Color = i == 2 ? Color(red: 1, green: 0.97, blue: 0.88) : i == 3 ? Color(red: 0.12, green: 0.16, blue: 0.21) : .white
                        let ink: Color = i == 2 ? Color(red: 0.16, green: 0.12, blue: 0.02) : i == 3 ? Color(red: 0.95, green: 0.87, blue: 0.63) : Color(white: 0.07)
                        Choice(name: Look.faces[i], selected: look.cardFace == i, pick: { look.cardFace = i }) {
                            Text(i == 1 ? "A" : "♠").font(.system(size: i == 1 ? 20 : 18, weight: .heavy)).foregroundColor(ink)
                                .frame(width: 30, height: 42).background(bg).clipShape(RoundedRectangle(cornerRadius: 5))
                                .overlay(RoundedRectangle(cornerRadius: 5).stroke(i >= 2 ? Color(red: 0.85, green: 0.71, blue: 0.35) : Color(white: 0.8), lineWidth: 1))
                        }
                    }
                }
                LookRow(title: "إطار الورق") {
                    ForEach(Look.cardEdges.indices, id: \.self) { i in
                        Choice(name: Look.cardEdges[i].name, selected: look.cardEdge == i, pick: { look.cardEdge = i }) {
                            RoundedRectangle(cornerRadius: 5).fill(.white).overlay(RoundedRectangle(cornerRadius: 5).stroke(Look.cardEdges[i].colors[0], lineWidth: 2)).frame(width: 28, height: 40)
                        }
                    }
                }
            case "domino":
                LookRow(title: "لون الطاولة") {
                    ForEach(Look.felts.indices, id: \.self) { i in
                        Choice(name: Look.felts[i].name, selected: look.dominoFelt == i, pick: { look.dominoFelt = i }) {
                            RoundedRectangle(cornerRadius: 12).fill(RadialGradient(colors: Look.felts[i].colors, center: .center, startRadius: 0, endRadius: 30)).frame(width: 40, height: 40)
                        }
                    }
                }
                LookRow(title: "حافة الطاولة") {
                    ForEach(Look.rims.indices, id: \.self) { i in
                        Choice(name: Look.rims[i].name, selected: look.dominoRim == i, pick: { look.dominoRim = i }) {
                            RoundedRectangle(cornerRadius: 10).fill(LinearGradient(colors: Look.rims[i].colors, startPoint: .top, endPoint: .bottom)).frame(width: 40, height: 40)
                        }
                    }
                }
                LookRow(title: "لون الأحجار") {
                    ForEach(Look.tiles.indices, id: \.self) { i in
                        let t = Look.tiles[i].colors
                        Choice(name: Look.tiles[i].name, selected: look.dominoTile == i, pick: { look.dominoTile = i }) {
                            RoundedRectangle(cornerRadius: 5).fill(t[0]).overlay(RoundedRectangle(cornerRadius: 5).stroke(t[2], lineWidth: 1))
                                .overlay(Circle().fill(t[1]).frame(width: 6, height: 6)).frame(width: 48, height: 24)
                        }
                    }
                }
                LookRow(title: "حجم الأحجار") {
                    ForEach(Look.sizes.indices, id: \.self) { i in
                        let s = Look.sizes[i].1
                        Choice(name: Look.sizes[i].0, selected: look.dominoSize == i, pick: { look.dominoSize = i }) {
                            RoundedRectangle(cornerRadius: 4).fill(Color(red: 0.98, green: 0.97, blue: 0.93)).frame(width: 22 * s, height: 40 * s)
                        }
                    }
                }
            case "jackaroo":
                LookRow(title: "لوحة الجاكارو") {
                    ForEach(Look.jkBoards.indices, id: \.self) { i in
                        let c = Look.jkBoards[i].colors
                        Choice(name: Look.jkBoards[i].name, selected: look.jkBoard == i, pick: { look.jkBoard = i }) {
                            OctagonShape().fill(LinearGradient(colors: [c[0], c[1]], startPoint: .topLeading, endPoint: .bottomTrailing))
                                .overlay(OctagonShape().fill(c[2]).frame(width: 14, height: 14)).frame(width: 42, height: 42)
                        }
                    }
                }
            default:
                LookRow(title: "نرد اللودو") {
                    ForEach(Look.dice.indices, id: \.self) { i in
                        let d = Look.dice[i].colors
                        Choice(name: Look.dice[i].name, selected: look.ludoDice == i, pick: { look.ludoDice = i }) {
                            RoundedRectangle(cornerRadius: 9).fill(d[0]).overlay(Circle().fill(d[1]).frame(width: 8, height: 8)).frame(width: 38, height: 38)
                        }
                    }
                }
            }
            Note("اختيارك يتحفظ على جوالك ويطلع لك أنت بس. اللي معك على الطاولة يشوفون الشكل اللي اختاروه هم.")
        }
    }

    @ViewBuilder private var preview: some View {
        switch game {
        case "baloot":
            let shape = Look.tableShape(look.balootShape)
            ZStack {
                shape.fill(RadialGradient(colors: Look.rims[look.balootRim].colors, center: .center, startRadius: 0, endRadius: 80))
                shape.fill(RadialGradient(colors: Look.felts[look.balootFelt].colors, center: .center, startRadius: 0, endRadius: 70)).padding(8)
                RoundedRectangle(cornerRadius: 5).fill(.white).overlay(RoundedRectangle(cornerRadius: 5).stroke(Look.cardEdges[look.cardEdge].colors[0], lineWidth: 2)).frame(width: 30, height: 42)
            }
            .frame(width: 140, height: 140)
            .rotation3DEffect(.degrees(40), axis: (x: 1, y: 0, z: 0), perspective: 0.65)
        case "domino":
            let t = Look.tiles[look.dominoTile].colors
            let s = Look.sizes[look.dominoSize].1
            RoundedRectangle(cornerRadius: 14).fill(RadialGradient(colors: Array(Look.felts[look.dominoFelt].colors.prefix(2)), center: .center, startRadius: 0, endRadius: 120))
                .overlay(
                    HStack(spacing: 0) {
                        Circle().fill(t[1]).frame(width: 6, height: 6).frame(maxWidth: .infinity)
                        Rectangle().fill(t[1].opacity(0.8)).frame(width: 1.5, height: 24 * s)
                        HStack { Circle().fill(t[1]).frame(width: 6, height: 6); Circle().fill(t[1]).frame(width: 6, height: 6) }.frame(maxWidth: .infinity)
                    }
                    .frame(width: 64 * s, height: 32 * s).background(t[0]).clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(t[2], lineWidth: 1))
                )
                .padding(5)
                .background(RoundedRectangle(cornerRadius: 18).fill(LinearGradient(colors: Look.rims[look.dominoRim].colors, startPoint: .top, endPoint: .bottom)))
                .frame(width: 230, height: 130)
        case "jackaroo":
            let c = Look.jkBoards[look.jkBoard].colors
            OctagonShape().fill(LinearGradient(colors: [c[0], c[1]], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(OctagonShape().fill(c[2]).frame(width: 40, height: 40)).frame(width: 130, height: 130)
        default:
            let d = Look.dice[look.ludoDice].colors
            ZStack {
                RoundedRectangle(cornerRadius: 16).fill(d[0]).shadow(color: .black.opacity(0.5), radius: 8, y: 5)
                Circle().fill(d[1]).frame(width: 10, height: 10).offset(x: -18, y: -18)
                Circle().fill(d[1]).frame(width: 10, height: 10)
                Circle().fill(d[1]).frame(width: 10, height: 10).offset(x: 18, y: 18)
            }
            .frame(width: 70, height: 70)
        }
    }
}
