package app.laqta.laqta

import java.io.File

/** One clip to render: a media file and the part of it to use. */
data class ExportClip(val file: File, val startUs: Long, val endUs: Long)

/** A validated export request. */
data class ParsedExportRequest(
    val output: File,
    val width: Int,
    val height: Int,
    val clips: List<ExportClip>,
)

/**
 * Validates the map sent from Dart (`ExportRequest.toMap`).
 *
 * Never trusts the caller: every clip must be a regular file inside
 * [mediaDir] (the app's private media library) and the output must be inside
 * [exportDir]. Paths are compared after resolving `..` and symlinks, so no
 * spelling of a path can read or write anything else on the device.
 */
object ExportRequestParser {
    // Dart sends at most 1080p (1920 on the long side).
    const val MAX_SIDE = 1920
    const val MAX_CLIPS = 500
    private const val MIN_CLIP_US = 100_000L

    fun parse(args: Any?, mediaDir: File, exportDir: File): ParsedExportRequest {
        val map = args as? Map<*, *> ?: invalid("arguments must be a map")

        val width = map["width"].asInt("width")
        val height = map["height"].asInt("height")
        require(width in 2..MAX_SIDE && height in 2..MAX_SIDE) { "size out of range" }
        require(width % 2 == 0 && height % 2 == 0) { "size must be even" }

        val output = File(map["outputPath"] as? String ?: invalid("outputPath missing")).canonicalFile
        require(isInside(output, exportDir)) { "output outside export directory" }
        require(output.name.endsWith(".mp4")) { "output must be .mp4" }

        val rawClips = map["clips"] as? List<*> ?: invalid("clips missing")
        require(rawClips.isNotEmpty()) { "no clips" }
        require(rawClips.size <= MAX_CLIPS) { "too many clips" }

        val clips = rawClips.map { raw ->
            val clip = raw as? Map<*, *> ?: invalid("clip must be a map")
            // Canonical path is what we hand to Transformer, so the file we
            // checked is the file that gets opened.
            val file = File(clip["path"] as? String ?: invalid("clip path missing")).canonicalFile
            require(isInside(file, mediaDir)) { "clip outside media library" }
            require(file.isFile) { "clip file missing" }
            val start = clip["startUs"].asLong("startUs")
            val end = clip["endUs"].asLong("endUs")
            // end > start first, so end - start cannot overflow.
            require(start >= 0 && end > start && end - start >= MIN_CLIP_US) { "invalid clip range" }
            ExportClip(file, start, end)
        }
        return ParsedExportRequest(output, width, height, clips)
    }

    /** True if [file] resolves to an entry directly inside [dir]. */
    fun isInside(file: File, dir: File): Boolean =
        file.canonicalFile.parentFile == dir.canonicalFile

    private fun Any?.asInt(name: String): Int = when (this) {
        is Int -> this
        is Long -> if (this in Int.MIN_VALUE..Int.MAX_VALUE) toInt() else invalid("$name too large")
        else -> invalid("$name must be an integer")
    }

    private fun Any?.asLong(name: String): Long = when (this) {
        is Int -> toLong()
        is Long -> this
        else -> invalid("$name must be an integer")
    }

    private fun invalid(message: String): Nothing = throw IllegalArgumentException(message)
}
