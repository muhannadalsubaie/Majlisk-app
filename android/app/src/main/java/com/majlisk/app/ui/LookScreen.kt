package com.majlisk.app.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.CutCornerShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.majlisk.app.a11y.Announcer
import com.majlisk.app.data.Look

/** خيار واحد: مربع يبين الشكل، واسمه تحته، ويُقرأ «الاسم، مختار» */
@Composable
private fun Choice(name: String, selected: Boolean, onPick: () -> Unit, swatch: @Composable () -> Unit) {
    Column(
        Modifier.width(86.dp).clip(RoundedCornerShape(16.dp)).background(Pro.deep)
            .border(if (selected) 2.dp else 1.dp, if (selected) Pro.gold else Pro.goldLight.copy(alpha = 0.2f), RoundedCornerShape(16.dp))
            .clickable(role = Role.Button) { onPick(); Announcer.announce("اخترت $name") }
            .semantics(mergeDescendants = true) { contentDescription = name; this.selected = selected }
            .padding(vertical = 10.dp, horizontal = 4.dp),
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Box(Modifier.height(44.dp).clearAndSetSemantics { }, contentAlignment = Alignment.Center) { swatch() }
        Text(name, color = if (selected) Pro.goldLight else Color(0xFFF4EFE2), fontSize = 12.sp, fontWeight = FontWeight.Bold, textAlign = TextAlign.Center,
            modifier = Modifier.clearAndSetSemantics { })
    }
}

@Composable
private fun Section(title: String, content: @Composable () -> Unit) {
    SectionTitle(title)
    Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(10.dp)) { content() }
}

private fun shapeOf(i: Int): Shape = when (i) {
    1 -> RoundedCornerShape(26)
    2 -> CutCornerShape(29)
    3 -> RoundedCornerShape(6)
    else -> CircleShape
}

/**
 * تخصيص الشكل (الباقة الاحترافية): طاولة البلوت وورقها، والدومينو، ولوحة الجاكارو، ونرد اللودو.
 * الاختيار يتحفظ في جوالك ويطلع لك أنت بس.
 */
@Composable
fun LookScreen(onBack: () -> Unit) {
    var game by remember { mutableStateOf("baloot") }
    val pick = { f: () -> Unit -> f(); Look.save() }
    Screen {
        TopBar("تخصيص الشكل", onBack = onBack)
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            listOf("baloot" to "بلوت", "domino" to "دومينو", "jackaroo" to "جاكارو", "ludo" to "لودو").forEach { (id, label) ->
                if (game == id) GoldButton(label, {}, Modifier.weight(1f)) else SecondaryButton(label, { game = id }, Modifier.weight(1f), fill = true)
            }
        }
        // معاينة
        Box(Modifier.fillMaxWidth().height(170.dp).clip(RoundedCornerShape(22.dp)).background(Brush.linearGradient(listOf(Color(0xFF23303D), Pro.night))).clearAndSetSemantics { },
            contentAlignment = Alignment.Center) {
            when (game) {
                "baloot" -> Box(Modifier.widthIn(max = 150.dp).fillMaxWidth().aspectRatio(1f).graphicsLayer { rotationX = 40f; cameraDistance = 12f * density }
                    .shadow(12.dp, shapeOf(Look.balootShape)).background(Brush.radialGradient(Look.RIMS[Look.balootRim].colors), shapeOf(Look.balootShape)).padding(8.dp)
                    .clip(shapeOf(Look.balootShape)).background(Brush.radialGradient(Look.FELTS[Look.balootFelt].colors)), contentAlignment = Alignment.Center) {
                    Box(Modifier.size(30.dp, 42.dp).background(Color.White, RoundedCornerShape(5.dp)).border(2.dp, Look.CARD_EDGES[Look.cardEdge].colors[0], RoundedCornerShape(5.dp)))
                }
                "domino" -> Box(Modifier.size(230.dp, 130.dp).background(Brush.verticalGradient(Look.RIMS[Look.dominoRim].colors), RoundedCornerShape(18.dp)).padding(5.dp)
                    .background(Brush.radialGradient(Look.FELTS[Look.dominoFelt].colors.take(2)), RoundedCornerShape(14.dp)), contentAlignment = Alignment.Center) {
                    val t = Look.TILES[Look.dominoTile].colors
                    val s = Look.SIZES[Look.dominoSize].second
                    Row(Modifier.background(t[0], RoundedCornerShape(6.dp)).border(1.dp, t[2], RoundedCornerShape(6.dp)).size((64 * s).dp, (32 * s).dp), verticalAlignment = Alignment.CenterVertically) {
                        Box(Modifier.weight(1f), contentAlignment = Alignment.Center) { Box(Modifier.size(6.dp).background(t[1], CircleShape)) }
                        Box(Modifier.width(1.5.dp).height((24 * s).dp).background(t[1].copy(alpha = 0.8f)))
                        Row(Modifier.weight(1f), horizontalArrangement = Arrangement.SpaceEvenly) { repeat(2) { Box(Modifier.size(6.dp).background(t[1], CircleShape)) } }
                    }
                }
                "jackaroo" -> Box(Modifier.size(130.dp).background(Brush.linearGradient(Look.JK_BOARDS[Look.jkBoard].colors.take(2)), CutCornerShape(29)), contentAlignment = Alignment.Center) {
                    Box(Modifier.size(40.dp).background(Look.JK_BOARDS[Look.jkBoard].colors[2], CutCornerShape(29)))
                }
                else -> {
                    val d = Look.DICE[Look.ludoDice].colors
                    Box(Modifier.size(70.dp).shadow(8.dp, RoundedCornerShape(16.dp)).background(d[0], RoundedCornerShape(16.dp)).padding(12.dp)) {
                        Box(Modifier.size(10.dp).background(d[1], CircleShape).align(Alignment.TopStart))
                        Box(Modifier.size(10.dp).background(d[1], CircleShape).align(Alignment.Center))
                        Box(Modifier.size(10.dp).background(d[1], CircleShape).align(Alignment.BottomEnd))
                    }
                }
            }
        }
        when (game) {
            "baloot" -> {
                Section("شكل الطاولة") {
                    Look.SHAPES.forEachIndexed { i, n -> Choice(n, Look.balootShape == i, { pick { Look.balootShape = i } }) {
                        Box(Modifier.size(48.dp, 36.dp).background(Color(0xFF1B7557), shapeOf(i)).border(3.dp, Color(0xFF8B5A2B), shapeOf(i)))
                    } }
                }
                Section("لون الطاولة") {
                    Look.FELTS.forEachIndexed { i, o -> Choice(o.name, Look.balootFelt == i, { pick { Look.balootFelt = i } }) {
                        Box(Modifier.size(40.dp).background(Brush.radialGradient(o.colors), RoundedCornerShape(12.dp)))
                    } }
                }
                Section("حافة الطاولة") {
                    Look.RIMS.forEachIndexed { i, o -> Choice(o.name, Look.balootRim == i, { pick { Look.balootRim = i } }) {
                        Box(Modifier.size(40.dp).background(Brush.verticalGradient(o.colors), CircleShape))
                    } }
                }
                Section("إطار الورق") {
                    Look.CARD_EDGES.forEachIndexed { i, o -> Choice(o.name, Look.cardEdge == i, { pick { Look.cardEdge = i } }) {
                        Box(Modifier.size(28.dp, 40.dp).background(Color.White, RoundedCornerShape(5.dp)).border(2.dp, o.colors[0], RoundedCornerShape(5.dp)))
                    } }
                }
            }
            "domino" -> {
                Section("لون الطاولة") {
                    Look.FELTS.forEachIndexed { i, o -> Choice(o.name, Look.dominoFelt == i, { pick { Look.dominoFelt = i } }) {
                        Box(Modifier.size(40.dp).background(Brush.radialGradient(o.colors), RoundedCornerShape(12.dp)))
                    } }
                }
                Section("حافة الطاولة") {
                    Look.RIMS.forEachIndexed { i, o -> Choice(o.name, Look.dominoRim == i, { pick { Look.dominoRim = i } }) {
                        Box(Modifier.size(40.dp).background(Brush.verticalGradient(o.colors), RoundedCornerShape(10.dp)))
                    } }
                }
                Section("لون الأحجار") {
                    Look.TILES.forEachIndexed { i, o -> Choice(o.name, Look.dominoTile == i, { pick { Look.dominoTile = i } }) {
                        Box(Modifier.size(48.dp, 24.dp).background(o.colors[0], RoundedCornerShape(5.dp)).border(1.dp, o.colors[2], RoundedCornerShape(5.dp)), contentAlignment = Alignment.Center) {
                            Box(Modifier.size(6.dp).background(o.colors[1], CircleShape))
                        }
                    } }
                }
                Section("حجم الأحجار") {
                    Look.SIZES.forEachIndexed { i, (n, s) -> Choice(n, Look.dominoSize == i, { pick { Look.dominoSize = i } }) {
                        Box(Modifier.size((22 * s).dp, (40 * s).dp).background(Color(0xFFFAF7EE), RoundedCornerShape(4.dp)))
                    } }
                }
            }
            "jackaroo" -> Section("لوحة الجاكارو") {
                Look.JK_BOARDS.forEachIndexed { i, o -> Choice(o.name, Look.jkBoard == i, { pick { Look.jkBoard = i } }) {
                    Box(Modifier.size(42.dp).background(Brush.linearGradient(o.colors.take(2)), CutCornerShape(29)), contentAlignment = Alignment.Center) {
                        Box(Modifier.size(14.dp).background(o.colors[2], CutCornerShape(29)))
                    }
                } }
            }
            else -> Section("نرد اللودو") {
                Look.DICE.forEachIndexed { i, o -> Choice(o.name, Look.ludoDice == i, { pick { Look.ludoDice = i } }) {
                    Box(Modifier.size(38.dp).background(o.colors[0], RoundedCornerShape(9.dp)), contentAlignment = Alignment.Center) {
                        Box(Modifier.size(8.dp).background(o.colors[1], CircleShape))
                    }
                } }
            }
        }
        Note("اختيارك يتحفظ على جوالك ويطلع لك أنت بس. اللي معك على الطاولة يشوفون الشكل اللي اختاروه هم.")
    }
}
