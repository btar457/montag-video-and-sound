package app.laqta.laqta

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File
import java.nio.file.Files

class ExportRequestParserTest {
    @get:Rule
    val tmp = TemporaryFolder()

    private lateinit var media: File
    private lateinit var exports: File
    private lateinit var clipA: File

    @Before
    fun setUp() {
        media = tmp.newFolder("app_flutter", "media")
        exports = tmp.newFolder("cache", "exports")
        clipA = File(media, "a.mp4").apply { writeText("v") }
    }

    private fun request(
        path: String = clipA.path,
        output: String = File(exports, "out.mp4").path,
        width: Any = 1080,
        height: Any = 1920,
        startUs: Any = 0,
        endUs: Any = 2_000_000,
    ): Map<String, Any?> = mapOf(
        "outputPath" to output,
        "width" to width,
        "height" to height,
        "clips" to listOf(mapOf("path" to path, "startUs" to startUs, "endUs" to endUs)),
    )

    private fun parse(args: Any?) = ExportRequestParser.parse(args, media, exports)

    private fun assertInvalid(args: Any?) {
        assertThrows(IllegalArgumentException::class.java) { parse(args) }
    }

    @Test
    fun validRequestIsParsed() {
        val r = parse(request())
        assertEquals(1080, r.width)
        assertEquals(1920, r.height)
        assertEquals(1, r.clips.size)
        assertEquals(clipA.canonicalFile, r.clips[0].file.canonicalFile)
        assertEquals(2_000_000L, r.clips[0].endUs)
    }

    @Test
    fun acceptsLongNumbersFromTheChannel() {
        val r = parse(request(width = 1080L, height = 1920L, endUs = 3_000_000L))
        assertEquals(3_000_000L, r.clips[0].endUs)
    }

    @Test
    fun rejectsClipsOutsideTheMediaLibrary() {
        val outside = tmp.newFile("secret.mp4")
        assertInvalid(request(path = outside.path))
        assertInvalid(request(path = File(media, "../../secret.mp4").path))
        assertInvalid(request(path = "/data/data/other.app/files/x.mp4"))
    }

    @Test
    fun rejectsSymlinkEscapingTheMediaLibrary() {
        val outside = tmp.newFile("private.mp4")
        val link = File(media, "link.mp4")
        Files.createSymbolicLink(link.toPath(), outside.toPath())
        assertInvalid(request(path = link.path))
    }

    @Test
    fun rejectsMissingClipFile() {
        assertInvalid(request(path = File(media, "gone.mp4").path))
    }

    @Test
    fun rejectsOutputOutsideExportDirOrNotMp4() {
        assertInvalid(request(output = File(media, "out.mp4").path))
        assertInvalid(request(output = File(exports, "../out.mp4").path))
        assertInvalid(request(output = File(exports, "out.txt").path))
    }

    @Test
    fun rejectsBadSizes() {
        assertInvalid(request(width = 1081))
        assertInvalid(request(width = 0))
        assertInvalid(request(height = 10_000))
        assertInvalid(request(width = 3840, height = 2160))
        assertInvalid(request(width = "1080"))
    }

    @Test
    fun rejectsBadRanges() {
        assertInvalid(request(startUs = -1))
        assertInvalid(request(startUs = 0, endUs = 99_999))
        assertInvalid(request(startUs = 5_000_000, endUs = 1_000_000))
        // end - start would overflow to a large positive number.
        assertInvalid(request(startUs = 1L shl 62, endUs = Long.MIN_VALUE))
    }

    @Test
    fun rejectsMalformedArguments() {
        assertInvalid(null)
        assertInvalid("nope")
        assertInvalid(request() - "clips")
        assertInvalid(request() + ("clips" to emptyList<Any>()))
        assertInvalid(request() + ("clips" to listOf("not a map")))
    }

    @Test
    fun isInsideRequiresDirectChild() {
        assertTrue(ExportRequestParser.isInside(File(media, "x.mp4"), media))
        assertFalse(ExportRequestParser.isInside(media, media))
        assertFalse(ExportRequestParser.isInside(File(media, "sub/x.mp4"), media))
        assertFalse(ExportRequestParser.isInside(File(media.path + "-evil", "x.mp4"), media))
    }

    @Test
    fun returnsCanonicalPaths() {
        val viaDots = File(media, "../media/a.mp4").path
        val r = parse(request(path = viaDots))
        assertEquals(clipA.canonicalFile.path, r.clips[0].file.path)
        assertEquals(File(exports, "out.mp4").canonicalFile.path, r.output.path)
    }

    @Test
    fun rejectsClipsInSubfoldersAndOutputInSubfolders() {
        val sub = File(media, "sub").apply { mkdirs() }
        val nested = File(sub, "n.mp4").apply { writeText("v") }
        assertInvalid(request(path = nested.path))
        assertInvalid(request(output = File(exports, "sub/out.mp4").path))
    }
}
