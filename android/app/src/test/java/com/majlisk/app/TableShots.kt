package com.majlisk.app

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.Text
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import com.github.takahirom.roborazzi.captureRoboImage
import com.majlisk.app.data.TableConnection
import com.majlisk.app.data.gameTitle
import com.majlisk.app.model.TableView
import com.majlisk.app.table.ChatButton
import com.majlisk.app.table.DominoBoard
import com.majlisk.app.table.JackarooBoard
import com.majlisk.app.table.LudoBoard
import com.majlisk.app.ui.BackButton
import com.majlisk.app.ui.MajliskTheme
import com.majlisk.app.ui.Palette
import com.majlisk.app.ui.Screen
import com.majlisk.app.voice.VoiceButton
import org.json.JSONObject
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/** صور الطاولات كما تظهر في الجوال (نفس ترتيب شاشة الطاولة)، من حالات لعب حقيقية من الخادم */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [34], qualifiers = "w400dp-h1000dp-xxhdpi")
class TableShots {
    private fun view(name: String): TableView =
        TableView.parse(JSONObject(javaClass.classLoader!!.getResource("fixtures/$name.json")!!.readText()))

    private fun shot(name: String) {
        val v = view(name)
        val conn = TableConnection(v.id)
        captureRoboImage("build/shots/android-$name.png") {
            CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Rtl) {
                MajliskTheme {
                    Screen(fill = true) {
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                            BackButton({}, "القائمة")
                            Text("طاولة ${if (v.kind == "domino") "دومينو ${v.optTarget}" else gameTitle(v.kind, v.variant)} — المالك ${v.ownerName}", color = Palette.textDim, modifier = Modifier.weight(1f), textAlign = TextAlign.End)
                        }
                        if (v.hasGame && v.ludo != null) Spacer(Modifier.weight(1f))
                        when {
                            !v.hasGame -> com.majlisk.app.table.SeatsLobby(v, "u1", conn)
                            v.game != null -> com.majlisk.app.table.BalootBoard(v, v.game!!, "u1", conn)
                            v.domino != null -> DominoBoard(v, v.domino!!, conn, true) {}
                            v.jackaroo != null -> JackarooBoard(v, v.jackaroo!!, conn, true)
                            v.ludo != null -> LudoBoard(v, v.ludo!!, conn, true)
                        }
                        Spacer(Modifier.weight(1f))
                        v.domino?.let { com.majlisk.app.table.DominoHand(v, it, conn) {} }
                        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp, Alignment.End), verticalAlignment = Alignment.CenterVertically) {
                            ChatButton(conn) {}
                            VoiceButton(v.id, "u1")
                        }
                    }
                }
            }
        }
    }

    @Test fun domino() = shot("domino")
    @Test fun jackaroo() = shot("jackaroo")
    @Test fun ludo() = shot("ludo")
    @Test fun baloot() = shot("baloot")
    @Test fun balootBid() = shot("baloot-bid")
    @Test fun lobby() = shot("lobby")
}
