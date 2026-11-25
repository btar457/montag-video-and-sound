package app.laqta.laqta

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var export: ExportHandler? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val handler = ExportHandler(applicationContext)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        MethodChannel(messenger, ExportHandler.METHOD_CHANNEL).setMethodCallHandler(handler)
        EventChannel(messenger, ExportHandler.EVENT_CHANNEL).setStreamHandler(handler)
        export = handler
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        export?.dispose()
        export = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
