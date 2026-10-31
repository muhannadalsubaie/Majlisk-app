package com.majlisk.app.data

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

/** رسالة في دردشة الطاولة الكتابية */
data class ChatMessage(val uid: String, val name: String, val text: String, val mine: Boolean)

/**
 * اختيار كل لاعب للدردشة الكتابية (له وحده، ويُحفظ لكل الطاولات):
 * READ توصله ويقرأها قارئ الشاشة، SILENT توصله بلا قراءة، OFF ما توصله ولا يرسل.
 */
enum class ChatMode(val key: String, val label: String) {
    READ("read", "توصلني ويقرأها قارئ الشاشة"),
    SILENT("silent", "توصلني بدون قراءة (أرجع لها بنفسي)"),
    OFF("off", "مطفأة (ما توصلني ولا أرسل)"),
}

object ChatSettings {
    private val _mode = MutableStateFlow(ChatMode.entries.firstOrNull { it.key == Prefs.chatMode } ?: ChatMode.READ)
    val mode: StateFlow<ChatMode> = _mode
    fun set(m: ChatMode) { Prefs.chatMode = m.key; _mode.value = m }
}
