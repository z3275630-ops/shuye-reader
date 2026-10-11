package dev.shuye.shuye_reader

import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMethodCodec

/**
 * Adapt Flutter's fix 3ec72ae / PR #189823 without replacing the pinned engine:
 * https://github.com/flutter/flutter/pull/189823
 *
 * Reuse the engine's parser/plugin, move PackageManager queries and label disk
 * reads to its serial TaskQueue. Launching activities and handling their results
 * remain on Android's main thread, as in the upstream fix. Our reading toolbar
 * keeps its existing copy/note actions; other text fields keep native actions.
 * Remove this adapter when the pinned embedding includes the upstream fix.
 */
internal fun installProcessTextQueue(engine: FlutterEngine) {
    val messenger = engine.dartExecutor.binaryMessenger
    val parser = engine.processTextChannel.parsingMethodHandler
    val mainThread = Handler(Looper.getMainLooper())
    // Register on the same channel, replacing its original main-thread handler.
    MethodChannel(
        messenger,
        "flutter/processtext",
        StandardMethodCodec.INSTANCE,
        messenger.makeBackgroundTaskQueue(),
    ).setMethodCallHandler { call, result ->
        if (call.method == "ProcessText.queryTextActions") {
            parser.onMethodCall(call, result)
        } else {
            mainThread.post { parser.onMethodCall(call, result) }
        }
    }
}
