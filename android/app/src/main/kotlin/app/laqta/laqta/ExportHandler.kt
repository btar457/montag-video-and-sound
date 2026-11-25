package app.laqta.laqta

import android.content.Context
import android.os.Handler
import android.os.Looper
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.effect.Presentation
import androidx.media3.transformer.Composition
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.EditedMediaItemSequence
import androidx.media3.transformer.Effects
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.ProgressHolder
import androidx.media3.transformer.Transformer
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Renders a project with Media3 Transformer. Protocol documented in
 * `lib/features/export/export_engine.dart`. Everything runs on the main
 * looper, which Transformer requires for its callbacks.
 */
class ExportHandler(private val context: Context) :
    MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    companion object {
        const val METHOD_CHANNEL = "app.laqta/export"
        const val EVENT_CHANNEL = "app.laqta/export/events"
        private const val PROGRESS_INTERVAL_MS = 250L
    }

    // Must match lib/main.dart: path_provider's documents dir is app_flutter.
    private val mediaDir: File get() = File(context.getDir("flutter", Context.MODE_PRIVATE), "media")
    private val exportDir: File get() = File(context.cacheDir, "exports")

    private val main = Handler(Looper.getMainLooper())
    private var sink: EventChannel.EventSink? = null
    private var transformer: Transformer? = null
    private var output: File? = null
    private val progress = ProgressHolder()

    private val poll = object : Runnable {
        override fun run() {
            val t = transformer ?: return
            val fraction = if (t.getProgress(progress) == Transformer.PROGRESS_STATE_AVAILABLE) {
                progress.progress / 100.0
            } else {
                null
            }
            send(mapOf("type" to "progress", "fraction" to fraction))
            main.postDelayed(this, PROGRESS_INTERVAL_MS)
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "start" -> start(call.arguments, result)
            "cancel" -> {
                cancel()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun start(args: Any?, result: MethodChannel.Result) {
        if (transformer != null) {
            result.error("busy", "An export is already running", null)
            return
        }
        val request = try {
            exportDir.mkdirs()
            ExportRequestParser.parse(args, mediaDir, exportDir)
        } catch (e: IllegalArgumentException) {
            // Our own messages name the failed check only, never a path.
            result.error("invalid_input", e.message, null)
            return
        } catch (e: Exception) {
            // e.g. IOException from canonicalFile: must still reach Dart.
            result.error("invalid_input", null, null)
            return
        }

        try {
            begin(request)
            result.success(null)
        } catch (e: Exception) {
            // Builder or start() failed: reset so later exports still work.
            request.output.delete()
            finish()
            result.error("start_failed", null, null)
        }
    }

    private fun begin(request: ParsedExportRequest) {

        val items = request.clips.map { clip ->
            val mediaItem = MediaItem.Builder()
                .setUri(android.net.Uri.fromFile(clip.file))
                .setClippingConfiguration(
                    MediaItem.ClippingConfiguration.Builder()
                        .setStartPositionUs(clip.startUs)
                        .setEndPositionUs(clip.endUs)
                        .build(),
                )
                .build()
            EditedMediaItem.Builder(mediaItem).build()
        }
        val composition = Composition.Builder(EditedMediaItemSequence.Builder(items).build())
            // Clips without sound (e.g. screen recordings) get silence, so
            // they can be joined with clips that have audio.
            .experimentalSetForceAudioTrack(true)
            // Modern phones record HDR; H.264 output is SDR.
            .setHdrMode(Composition.HDR_MODE_TONE_MAP_HDR_TO_SDR_USING_OPEN_GL)
            // Every clip is scaled to fit the chosen frame (black bars if needed).
            .setEffects(
                Effects(
                    emptyList(),
                    listOf(
                        Presentation.createForWidthAndHeight(
                            request.width,
                            request.height,
                            Presentation.LAYOUT_SCALE_TO_FIT,
                        ),
                    ),
                ),
            )
            .build()

        lateinit var thisTransformer: Transformer
        val t = Transformer.Builder(context)
            .setVideoMimeType(MimeTypes.VIDEO_H264)
            .setAudioMimeType(MimeTypes.AUDIO_AAC)
            .addListener(object : Transformer.Listener {
                override fun onCompleted(composition: Composition, exportResult: ExportResult) {
                    if (transformer !== thisTransformer) return // cancelled or superseded
                    finish()
                    send(mapOf("type" to "done", "outputPath" to request.output.path))
                }

                override fun onError(
                    composition: Composition,
                    exportResult: ExportResult,
                    exportException: ExportException,
                ) {
                    if (transformer !== thisTransformer) return
                    request.output.delete()
                    finish()
                    send(mapOf("type" to "error", "code" to "transformer_${exportException.errorCode}"))
                }
            })
            .build()

        thisTransformer = t
        transformer = t
        output = request.output
        request.output.delete() // never append to a stale file
        t.start(composition, request.output.path)
        main.post(poll)
    }

    private fun cancel() {
        val t = transformer ?: return
        val file = output
        // Clear state first: late callbacks from t are ignored from now on.
        finish()
        try {
            t.cancel()
        } catch (e: Exception) {
            // Releasing codecs can fail; the export is abandoned either way.
        } finally {
            file?.delete()
            send(mapOf("type" to "cancelled"))
        }
    }

    private fun finish() {
        main.removeCallbacks(poll)
        transformer = null
        output = null
    }

    private fun send(event: Map<String, Any?>) {
        sink?.success(event)
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
    }

    override fun onCancel(arguments: Any?) {
        sink = null
    }

    /** Called when the activity is destroyed. */
    fun dispose() {
        cancel()
        sink = null
    }
}
