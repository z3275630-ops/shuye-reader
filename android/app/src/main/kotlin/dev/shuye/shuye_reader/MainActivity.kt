package dev.shuye.shuye_reader

import android.content.Intent
import android.content.pm.ActivityInfo
import android.os.Bundle
import android.os.Build
import android.Manifest
import android.content.pm.PackageManager
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.view.KeyEvent
import android.view.WindowManager
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import com.ryanheise.audioservice.AudioServiceFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

class MainActivity : AudioServiceFragmentActivity() {
    private var channel: MethodChannel? = null
    private var volumeKeys = false
    private var fullscreen = false
    private fun applyFullscreen() {
        val controller = WindowCompat.getInsetsController(window, window.decorView)
        controller.systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        if (fullscreen) controller.hide(WindowInsetsCompat.Type.systemBars())
        else controller.show(WindowInsetsCompat.Type.systemBars())
    }
    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus && fullscreen) applyFullscreen()
    }
    private var tts: TextToSpeech? = null
    private var ttsReady = false
    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        channel = MethodChannel(engine.dartExecutor.binaryMessenger, "dev.shuye/reader")
        tts = TextToSpeech(this) { status ->
            ttsReady = status == TextToSpeech.SUCCESS
            if (ttsReady) {
                tts?.language = Locale.SIMPLIFIED_CHINESE
                tts?.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                    override fun onStart(id: String?) {}
                    override fun onDone(id: String?) { runOnUiThread { channel?.invokeMethod("ttsDone", id) } }
                    override fun onError(id: String?) { runOnUiThread { channel?.invokeMethod("ttsError", id) } }
                })
            }
        }
        channel?.setMethodCallHandler { call, result ->
            try { when(call.method) {
                "audioNotification" -> { if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 8201); result.success(null) }
                "secure" -> {if(call.arguments == true)window.addFlags(WindowManager.LayoutParams.FLAG_SECURE) else window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE);result.success(null)}
                "fullscreen" -> {
                    fullscreen = call.arguments == true
                    applyFullscreen()
                    result.success(null)
                }
                "configure" -> {
                    volumeKeys = call.argument<Boolean>("volumeKeys") ?: false
                    if (call.argument<Boolean>("keepOn") == true) window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    else window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    val params = window.attributes
                    params.screenBrightness = (call.argument<Double>("brightness") ?: -1.0).toFloat().coerceIn(-1f,1f)
                    window.attributes = params
                    requestedOrientation = when(call.argument<String>("orientation")) { "portrait" -> ActivityInfo.SCREEN_ORIENTATION_PORTRAIT; "landscape" -> ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE; else -> ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED }
                    result.success(null)
                }
                "speak" -> {
                    if (!ttsReady) result.error("tts", "系统语音尚未准备好，请检查手机的文字转语音设置", null)
                    else {
                        val voice = call.argument<String>("voice")
                        if (!voice.isNullOrEmpty()) tts?.voices?.find { it.name == voice }?.let { tts?.voice = it }
                        tts?.setSpeechRate((call.argument<Double>("rate") ?: 1.0).toFloat())
                        val text = call.argument<String>("text") ?: ""
                        val status = tts?.speak(text.take(TextToSpeech.getMaxSpeechInputLength()), TextToSpeech.QUEUE_FLUSH, Bundle(), "shuye-page")
                        if(status == TextToSpeech.ERROR) result.error("tts", "手机未安装可用的中文语音，请在系统中下载语音包",null) else result.success(null)
                    }
                }
                "voices" -> result.success(tts?.voices?.map { mapOf("name" to it.name, "language" to it.locale.toLanguageTag(), "network" to it.isNetworkConnectionRequired) } ?: emptyList<Any>())
                "stopSpeech" -> {tts?.stop(); result.success(null)}
                "speechSettings" -> {startActivity(Intent("com.android.settings.TTS_SETTINGS"));result.success(null)}
                "widgets" -> {
                    val prefs = getSharedPreferences("shuye_widgets", MODE_PRIVATE).edit()
                    (call.arguments as? Map<*,*>)?.forEach { (k,v) -> prefs.putString(k.toString(),v.toString()) }
                    prefs.apply()
                    ShuyeWidget.refresh(this)
                    result.success(null)
                }
                "initialLink" -> result.success(intent?.dataString)
                else -> result.notImplemented()
            } } catch (e: Exception) {
                result.error("reader_platform", "手机操作未完成：${e.message ?: e.javaClass.simpleName}", null)
            }
        }
    }
    override fun onNewIntent(intent: Intent) { super.onNewIntent(intent); setIntent(intent); channel?.invokeMethod("link",intent.dataString) }
    override fun onKeyDown(code: Int,event: KeyEvent): Boolean {
        if(volumeKeys && (code == KeyEvent.KEYCODE_VOLUME_DOWN || code == KeyEvent.KEYCODE_VOLUME_UP)) {
            if(event.repeatCount == 0) channel?.invokeMethod("turn",if(code == KeyEvent.KEYCODE_VOLUME_DOWN) 1 else -1)
            return true
        }
        return super.onKeyDown(code,event)
    }
    override fun onKeyUp(code: Int,event: KeyEvent): Boolean {
        if(volumeKeys && (code == KeyEvent.KEYCODE_VOLUME_DOWN || code == KeyEvent.KEYCODE_VOLUME_UP)) return true
        return super.onKeyUp(code,event)
    }
    override fun onDestroy() {tts?.stop();tts?.shutdown();super.onDestroy()}
}
