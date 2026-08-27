package io.picklogic.picklogic_android_bridge

import android.Manifest
import android.app.Activity
import android.content.ContentResolver
import android.content.ContentUris
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.graphics.pdf.PdfRenderer
import android.os.StatFs
import android.provider.MediaStore
import android.util.Size
import android.util.Xml
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.PluginRegistry
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileOutputStream
import java.io.InputStreamReader
import java.nio.charset.StandardCharsets
import java.util.UUID
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.zip.ZipInputStream
import org.xmlpull.v1.XmlPullParser

internal fun hasRequestedMediaAccess(
    sdkInt: Int,
    state: Map<String, Boolean>,
): Boolean {
    val fullVisual = state["images"] == true && state["videos"] == true
    val selectedVisual = sdkInt >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE &&
        state["partialVisualAccess"] == true
    return (fullVisual || selectedVisual) && state["audio"] == true
}

internal fun mediaSortOrder(hasImageColumns: Boolean): String {
    val primary = if (hasImageColumns) {
        "CASE WHEN ${MediaStore.Images.ImageColumns.DATE_TAKEN} > 0 " +
            "THEN ${MediaStore.Images.ImageColumns.DATE_TAKEN} / 1000 " +
            "ELSE ${MediaStore.MediaColumns.DATE_MODIFIED} END"
    } else {
        MediaStore.MediaColumns.DATE_MODIFIED
    }
    return "$primary DESC, ${MediaStore.MediaColumns._ID} DESC"
}

internal fun mediaSourceHint(
    ownerPackage: String?,
    bucket: String?,
    pathHint: String?,
): String? {
    val meaningfulOwner = ownerPackage
        ?.trim()
        ?.takeIf { it.isNotEmpty() && it != "com.android.shell" && it != "android" }
    return meaningfulOwner ?: bucket ?: pathHint
}

private data class BoundedOfficePart(
    val bytes: ByteArray,
    val truncated: Boolean,
)

/** Read-only Android metadata bridge for PickLogic. */
class PicklogicAndroidBridgePlugin :
    FlutterPlugin,
    MethodChannel.MethodCallHandler,
    ActivityAware,
    PluginRegistry.RequestPermissionsResultListener,
    PluginRegistry.ActivityResultListener {
    private lateinit var channel: MethodChannel
    private lateinit var applicationContext: Context
    private var executor: ExecutorService? = null
    private var activityBinding: ActivityPluginBinding? = null
    private var pendingPermissionResult: MethodChannel.Result? = null
    private var pendingTreeResult: MethodChannel.Result? = null
    private var pendingWorkspaceTreeResult: MethodChannel.Result? = null
    private var pendingWorkspaceImportResult: MethodChannel.Result? = null
    private var pendingTrashResult: MethodChannel.Result? = null
    private lateinit var workspace: AndroidWorkspaceManager
    private lateinit var readOnlyBrowser: AndroidReadOnlyBrowser
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        applicationContext = binding.applicationContext
        workspace = AndroidWorkspaceManager(applicationContext)
        readOnlyBrowser = AndroidReadOnlyBrowser(applicationContext)
        executor = Executors.newSingleThreadExecutor { runnable ->
            Thread(runnable, "picklogic-media-index").apply { isDaemon = true }
        }
        channel = MethodChannel(binding.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        when (call.method) {
            "getPlatformVersion" -> result.success("Android ${Build.VERSION.RELEASE}")
            "getMediaPermissionState" -> result.success(mediaPermissionState())
            "requestMediaPermissions" -> requestMediaPermissions(result)
            "getStorageSnapshot" -> result.success(storageSnapshot())
            "getPrivateIndexDatabasePath" -> result.success(
                File(applicationContext.noBackupFilesDir, PRIVATE_INDEX_FILENAME).absolutePath,
            )
            "queryMediaPage" -> queryMediaPage(call, result)
            "countMedia" -> countMedia(call, result)
            "loadThumbnail" -> loadBoundedThumbnail(call, result)
            "pickDocumentTree" -> pickDocumentTree(result)
            "getBrowseRoots" -> runReadTask(result, "browse_roots_failed") {
                readOnlyBrowser.roots()
            }
            "listBrowseDirectory" -> listBrowseDirectory(call, result)
            "inspectBrowseDirectory" -> inspectBrowseDirectory(call, result)
            "openContentUri" -> openContentUri(call, result)
            "loadPreviewImage" -> loadPreviewImage(call, result)
            "loadTextPreview" -> loadTextPreview(call, result)
            "listArchive" -> listArchive(call, result)
            "inspectApk" -> inspectApk(call, result)
            "getPdfInfo" -> getPdfInfo(call, result)
            "inspectOffice" -> inspectOffice(call, result)
            "renderPdfPage" -> renderPdfPage(call, result)
            "readIntPreference" -> readIntPreference(call, result)
            "writeIntPreference" -> writeIntPreference(call, result)
            "getTestWorkspaceState" -> runReadTask(result, "workspace_failed") {
                workspace.state()
            }
            "pickTestWorkspaceTree" -> pickTestWorkspaceTree(result)
            "importTestWorkspaceCopies" -> importTestWorkspaceCopies(result)
            "createTestWorkspaceFolder" -> workspaceCreateFolder(call, result)
            "renameTestWorkspaceItem" -> workspaceRename(call, result)
            "moveTestWorkspaceItem" -> workspaceMove(call, result)
            "trashTestWorkspaceItem" -> workspaceTrash(call, result)
            "undoTestWorkspaceOperation" -> workspaceUndo(call, result)
            "requestSystemTrash" -> requestSystemTrash(call, result)
            else -> result.notImplemented()
        }
    }

    private fun pickTestWorkspaceTree(result: MethodChannel.Result) {
        val activity = activityBinding?.activity
        if (activity == null) {
            result.error("activity_unavailable", "A visible activity is required.", null)
            return
        }
        if (pendingWorkspaceTreeResult != null) {
            result.error("request_in_progress", "A workspace picker is already open.", null)
            return
        }
        pendingWorkspaceTreeResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                    Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or
                    Intent.FLAG_GRANT_PREFIX_URI_PERMISSION,
            )
        }
        activity.startActivityForResult(intent, WORKSPACE_TREE_REQUEST)
    }

    private fun importTestWorkspaceCopies(result: MethodChannel.Result) {
        val activity = activityBinding?.activity
        if (activity == null) {
            result.error("activity_unavailable", "A visible activity is required.", null)
            return
        }
        if (pendingWorkspaceImportResult != null) {
            result.error("request_in_progress", "A sample picker is already open.", null)
            return
        }
        pendingWorkspaceImportResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            type = "*/*"
            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
            addCategory(Intent.CATEGORY_OPENABLE)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        activity.startActivityForResult(intent, WORKSPACE_IMPORT_REQUEST)
    }

    private fun workspaceCreateFolder(call: MethodCall, result: MethodChannel.Result) {
        val arguments = call.arguments as? Map<*, *>
        val parent = (arguments?.get("parentUri") as? String)?.let(Uri::parse)
        val name = arguments?.get("name") as? String
        if (name == null) {
            result.error("invalid_workspace_request", "A folder name is required.", null)
            return
        }
        runReadTask(result, "workspace_create_failed") { workspace.createFolder(parent, name) }
    }

    private fun workspaceRename(call: MethodCall, result: MethodChannel.Result) {
        val arguments = call.arguments as? Map<*, *>
        val document = (arguments?.get("documentUri") as? String)?.let(Uri::parse)
        val name = arguments?.get("name") as? String
        if (document == null || name == null) {
            result.error("invalid_workspace_request", "An item and name are required.", null)
            return
        }
        runReadTask(result, "workspace_rename_failed") { workspace.rename(document, name) }
    }

    private fun workspaceMove(call: MethodCall, result: MethodChannel.Result) {
        val arguments = call.arguments as? Map<*, *>
        val document = (arguments?.get("documentUri") as? String)?.let(Uri::parse)
        val sourceParent = (arguments?.get("sourceParentUri") as? String)?.let(Uri::parse)
        val targetParent = (arguments?.get("targetParentUri") as? String)?.let(Uri::parse)
        if (document == null || sourceParent == null || targetParent == null) {
            result.error("invalid_workspace_request", "Source and destination are required.", null)
            return
        }
        runReadTask(result, "workspace_move_failed") {
            workspace.move(document, sourceParent, targetParent)
        }
    }

    private fun workspaceTrash(call: MethodCall, result: MethodChannel.Result) {
        val arguments = call.arguments as? Map<*, *>
        val document = (arguments?.get("documentUri") as? String)?.let(Uri::parse)
        val sourceParent = (arguments?.get("sourceParentUri") as? String)?.let(Uri::parse)
        if (document == null || sourceParent == null) {
            result.error("invalid_workspace_request", "A workspace item is required.", null)
            return
        }
        runReadTask(result, "workspace_trash_failed") {
            workspace.trash(document, sourceParent)
        }
    }

    private fun workspaceUndo(call: MethodCall, result: MethodChannel.Result) {
        val operationId = (call.arguments as? Map<*, *>)?.get("operationId") as? String
        runReadTask(result, "workspace_undo_failed") { workspace.undo(operationId) }
    }

    private fun requestSystemTrash(call: MethodCall, result: MethodChannel.Result) {
        val activity = activityBinding?.activity
        val rawUris = (call.arguments as? Map<*, *>)?.get("contentUris") as? List<*>
        val uris = rawUris?.mapNotNull { (it as? String)?.let(Uri::parse) } ?: emptyList()
        if (activity == null || Build.VERSION.SDK_INT < Build.VERSION_CODES.R || uris.isEmpty()) {
            result.success(false)
            return
        }
        if (pendingTrashResult != null || uris.any { it.scheme != ContentResolver.SCHEME_CONTENT }) {
            result.error("invalid_trash_request", "A system trash request is already open or invalid.", null)
            return
        }
        pendingTrashResult = result
        val request = MediaStore.createTrashRequest(applicationContext.contentResolver, uris.take(100), true)
        activity.startIntentSenderForResult(
            request.intentSender,
            SYSTEM_TRASH_REQUEST,
            null,
            0,
            0,
            0,
        )
    }

    private fun readIntPreference(call: MethodCall, result: MethodChannel.Result) {
        val key = (call.arguments as? Map<*, *>)?.get("key") as? String
        if (!isAllowedIntPreference(key)) {
            result.error("invalid_preference", "This preference key is not allowed.", null)
            return
        }
        val preferences = applicationContext.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)
        result.success(if (preferences.contains(key)) preferences.getInt(key!!, 0) else null)
    }

    private fun listBrowseDirectory(call: MethodCall, result: MethodChannel.Result) {
        val arguments = call.arguments as? Map<*, *>
        val tree = (arguments?.get("treeUri") as? String)?.let(Uri::parse)
        val directory = (arguments?.get("directoryUri") as? String)?.let(Uri::parse)
        val offset = (arguments?.get("offset") as? Number)?.toInt() ?: 0
        val limit = (arguments?.get("limit") as? Number)?.toInt() ?: 200
        if (tree == null) {
            result.error("invalid_browse_request", "A persisted SAF tree is required.", null)
            return
        }
        runReadTask(result, "browse_directory_failed") {
            readOnlyBrowser.list(tree, directory, offset, limit)
        }
    }

    private fun inspectBrowseDirectory(call: MethodCall, result: MethodChannel.Result) {
        val arguments = call.arguments as? Map<*, *>
        val tree = (arguments?.get("treeUri") as? String)?.let(Uri::parse)
        val directory = (arguments?.get("directoryUri") as? String)?.let(Uri::parse)
        if (tree == null) {
            result.error("invalid_browse_request", "A persisted SAF tree is required.", null)
            return
        }
        runReadTask(result, "browse_directory_inspection_failed") {
            readOnlyBrowser.inspect(tree, directory)
        }
    }

    private fun writeIntPreference(call: MethodCall, result: MethodChannel.Result) {
        val arguments = call.arguments as? Map<*, *>
        val key = arguments?.get("key") as? String
        val value = (arguments?.get("value") as? Number)?.toInt()
        val validValue = when {
            key in GRID_INT_PREFERENCES -> value != null && value in 2..6
            key?.startsWith(PDF_PAGE_PREFERENCE_PREFIX) == true ->
                value != null && value in 0..100_000
            else -> false
        }
        if (!isAllowedIntPreference(key) || value == null || !validValue) {
            result.error("invalid_preference", "A bounded PickLogic preference is required.", null)
            return
        }
        applicationContext.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)
            .edit()
            .putInt(key, value)
            .apply()
        result.success(null)
    }

    private fun isAllowedIntPreference(key: String?): Boolean =
        key in GRID_INT_PREFERENCES ||
            (key?.startsWith(PDF_PAGE_PREFERENCE_PREFIX) == true &&
                key.length <= PDF_PAGE_PREFERENCE_PREFIX.length + 16)

    private fun contentUri(call: MethodCall): Uri? =
        (call.arguments as? Map<*, *>)
            ?.get("contentUri")
            ?.let { it as? String }
            ?.let(Uri::parse)
            ?.takeIf { it.scheme == ContentResolver.SCHEME_CONTENT }

    private fun runReadTask(
        result: MethodChannel.Result,
        errorCode: String,
        action: () -> Any?,
    ) {
        val worker = executor
        if (worker == null || worker.isShutdown) {
            result.error("bridge_unavailable", "The Android bridge is detached.", null)
            return
        }
        worker.execute {
            try {
                val value = action()
                mainHandler.post { result.success(value) }
            } catch (_: SecurityException) {
                mainHandler.post {
                    result.error(
                        "permission_denied",
                        "Android did not grant access to this content URI.",
                        null,
                    )
                }
            } catch (error: IllegalArgumentException) {
                mainHandler.post { result.error("invalid_request", error.message, null) }
            } catch (_: Exception) {
                mainHandler.post {
                    result.error(errorCode, "Android could not read this item.", null)
                }
            }
        }
    }

    private fun loadPreviewImage(call: MethodCall, result: MethodChannel.Result) {
        val uri = contentUri(call)
        if (uri == null) {
            result.error("invalid_preview_request", "A content URI is required.", null)
            return
        }
        runReadTask(result, "preview_failed") {
            val decoded = decodeSampledBitmap(
                applicationContext.contentResolver,
                uri,
                MAX_PREVIEW_DIMENSION,
                MAX_PREVIEW_DIMENSION,
            ) ?: throw IllegalArgumentException("The item is not a supported image.")
            val bounded = scaleToFit(decoded, MAX_PREVIEW_DIMENSION, MAX_PREVIEW_DIMENSION)
            if (bounded !== decoded) decoded.recycle()
            try {
                encodeWithinBudget(bounded, MAX_PREVIEW_BYTES)
                    ?: throw IllegalArgumentException("The preview exceeds the memory budget.")
            } finally {
                bounded.recycle()
            }
        }
    }

    private fun loadTextPreview(call: MethodCall, result: MethodChannel.Result) {
        val uri = contentUri(call)
        if (uri == null) {
            result.error("invalid_text_request", "A content URI is required.", null)
            return
        }
        runReadTask(result, "text_preview_failed") {
            val text = StringBuilder()
            var truncated = false
            applicationContext.contentResolver.openInputStream(uri)?.use { stream ->
                InputStreamReader(stream, StandardCharsets.UTF_8).use { reader ->
                    val buffer = CharArray(4096)
                    while (text.length <= MAX_TEXT_CHARACTERS) {
                        val count = reader.read(buffer)
                        if (count < 0) break
                        val remaining = MAX_TEXT_CHARACTERS - text.length
                        if (count > remaining) {
                            text.append(buffer, 0, remaining.coerceAtLeast(0))
                            truncated = true
                            break
                        }
                        text.append(buffer, 0, count)
                    }
                    if (!truncated && text.length == MAX_TEXT_CHARACTERS && reader.read() >= 0) {
                        truncated = true
                    }
                }
            } ?: throw IllegalArgumentException("The item could not be opened.")
            mapOf("text" to text.toString(), "truncated" to truncated)
        }
    }

    private fun listArchive(call: MethodCall, result: MethodChannel.Result) {
        val uri = contentUri(call)
        if (uri == null) {
            result.error("invalid_archive_request", "A content URI is required.", null)
            return
        }
        runReadTask(result, "archive_preview_failed") {
            val entries = mutableListOf<Map<String, Any>>()
            var totalEntries = 0
            var truncated = false
            applicationContext.contentResolver.openInputStream(uri)?.use { input ->
                ZipInputStream(input.buffered()).use { zip ->
                    while (true) {
                        val entry = zip.nextEntry ?: break
                        totalEntries += 1
                        if (entries.size < MAX_ARCHIVE_ENTRIES) {
                            entries += mapOf(
                                "name" to entry.name,
                                "directory" to entry.isDirectory,
                                "sizeBytes" to entry.size.coerceAtLeast(0L),
                                "compressedBytes" to entry.compressedSize.coerceAtLeast(0L),
                            )
                        } else {
                            truncated = true
                        }
                        zip.closeEntry()
                    }
                }
            } ?: throw IllegalArgumentException("The archive could not be opened.")
            mapOf(
                "entries" to entries,
                "totalEntries" to totalEntries,
                "truncated" to truncated,
            )
        }
    }

    private fun inspectOffice(call: MethodCall, result: MethodChannel.Result) {
        val uri = contentUri(call)
        val extension = call.argument<String>("extension")?.lowercase()
        if (uri == null || extension == null || extension !in OFFICE_EXTENSIONS) {
            result.error("invalid_office_request", "A supported Office content URI is required.", null)
            return
        }
        if (extension in LEGACY_OFFICE_EXTENSIONS) {
            result.success(
                mapOf(
                    "kind" to extension,
                    "title" to "",
                    "sections" to emptyList<String>(),
                    "gridRows" to emptyList<List<String>>(),
                    "imageCount" to 0,
                    "itemCount" to 0,
                    "truncated" to false,
                ),
            )
            return
        }
        runReadTask(result, "office_preview_failed") {
            val parts = linkedMapOf<String, ByteArray>()
            var totalPartBytes = 0
            var imageCount = 0
            var observedSlides = 0
            var truncated = false
            applicationContext.contentResolver.openInputStream(uri)?.use { input ->
                ZipInputStream(input.buffered()).use { zip ->
                    while (true) {
                        val entry = zip.nextEntry ?: break
                        val name = entry.name.replace('\\', '/')
                        if (!entry.isDirectory) {
                            if (name.startsWith("word/media/") ||
                                name.startsWith("ppt/media/") ||
                                name.startsWith("xl/media/")) {
                                imageCount += 1
                            }
                            if (name.matches(PPT_SLIDE_PATTERN)) observedSlides += 1
                            if (isRelevantOfficePart(extension, name) &&
                                parts.size < MAX_OFFICE_PARTS &&
                                totalPartBytes < MAX_OFFICE_TOTAL_BYTES) {
                                val remaining = MAX_OFFICE_TOTAL_BYTES - totalPartBytes
                                val part = readBoundedOfficePart(
                                    zip,
                                    minOf(MAX_OFFICE_PART_BYTES, remaining),
                                )
                                parts[name] = part.bytes
                                totalPartBytes += part.bytes.size
                                truncated = truncated || part.truncated
                            } else if (isRelevantOfficePart(extension, name)) {
                                truncated = true
                            }
                        }
                        zip.closeEntry()
                    }
                }
            } ?: throw IllegalArgumentException("The Office file could not be opened.")
            buildOfficePreview(
                extension = extension,
                parts = parts,
                imageCount = imageCount,
                observedSlides = observedSlides,
                truncated = truncated,
            )
        }
    }

    private fun isRelevantOfficePart(extension: String, name: String): Boolean =
        name == "docProps/core.xml" || when (extension) {
            "docx" -> name == "word/document.xml"
            "xlsx" -> name == "xl/workbook.xml" ||
                name == "xl/sharedStrings.xml" ||
                name.matches(XLSX_SHEET_PATTERN)
            "pptx" -> name.matches(PPT_SLIDE_PATTERN)
            else -> false
        }

    private fun readBoundedOfficePart(zip: ZipInputStream, limit: Int): BoundedOfficePart {
        val output = ByteArrayOutputStream(minOf(limit, 64 * 1024))
        val buffer = ByteArray(8192)
        var truncated = false
        while (output.size() < limit) {
            val count = zip.read(buffer)
            if (count < 0) break
            val writable = minOf(count, limit - output.size())
            output.write(buffer, 0, writable)
            if (writable < count) {
                truncated = true
                break
            }
        }
        if (!truncated && output.size() == limit && zip.read() >= 0) truncated = true
        return BoundedOfficePart(output.toByteArray(), truncated)
    }

    private fun buildOfficePreview(
        extension: String,
        parts: Map<String, ByteArray>,
        imageCount: Int,
        observedSlides: Int,
        truncated: Boolean,
    ): Map<String, Any> {
        val title = extractXmlTexts(parts["docProps/core.xml"], setOf("title"), 1)
            .firstOrNull()
            .orEmpty()
        return when (extension) {
            "docx" -> {
                val document = parts["word/document.xml"]
                val text = extractXmlTexts(document, setOf("t"), 2000)
                    .joinToString(" ")
                    .take(MAX_OFFICE_SUMMARY_CHARS)
                mapOf(
                    "kind" to extension,
                    "title" to title,
                    "sections" to if (text.isEmpty()) emptyList<String>() else listOf(text),
                    "gridRows" to emptyList<List<String>>(),
                    "imageCount" to imageCount,
                    "itemCount" to countXmlElements(document, "p"),
                    "truncated" to (truncated || text.length == MAX_OFFICE_SUMMARY_CHARS),
                )
            }
            "xlsx" -> {
                val sheets = extractSheetNames(parts["xl/workbook.xml"])
                val shared = extractSharedStrings(parts["xl/sharedStrings.xml"])
                val firstSheet = parts.entries
                    .filter { it.key.matches(XLSX_SHEET_PATTERN) }
                    .minByOrNull { officePartNumber(it.key) }
                    ?.value
                mapOf(
                    "kind" to extension,
                    "title" to title,
                    "sections" to sheets,
                    "gridRows" to extractSheetRows(firstSheet, shared),
                    "imageCount" to imageCount,
                    "itemCount" to sheets.size,
                    "truncated" to truncated,
                )
            }
            else -> {
                val slides = parts.entries
                    .filter { it.key.matches(PPT_SLIDE_PATTERN) }
                    .sortedBy { officePartNumber(it.key) }
                    .mapIndexedNotNull { index, entry ->
                        val text = extractXmlTexts(entry.value, setOf("t"), 120)
                            .joinToString(" ")
                            .trim()
                            .take(1200)
                        text.takeIf { it.isNotEmpty() }?.let { "${index + 1}. $it" }
                    }
                mapOf(
                    "kind" to extension,
                    "title" to (title.ifEmpty { slides.firstOrNull()?.substringAfter(". ").orEmpty() }),
                    "sections" to slides,
                    "gridRows" to emptyList<List<String>>(),
                    "imageCount" to imageCount,
                    "itemCount" to observedSlides,
                    "truncated" to truncated,
                )
            }
        }
    }

    private fun newBoundedXmlParser(bytes: ByteArray?): XmlPullParser? {
        if (bytes == null || bytes.isEmpty()) return null
        return Xml.newPullParser().apply {
            setInput(ByteArrayInputStream(bytes), StandardCharsets.UTF_8.name())
        }
    }

    private fun extractXmlTexts(
        bytes: ByteArray?,
        elementNames: Set<String>,
        limit: Int,
    ): List<String> {
        val parser = newBoundedXmlParser(bytes) ?: return emptyList()
        val values = mutableListOf<String>()
        var captureDepth = -1
        var current = StringBuilder()
        while (parser.eventType != XmlPullParser.END_DOCUMENT && values.size < limit) {
            when (parser.eventType) {
                XmlPullParser.START_TAG -> if (parser.name.substringAfter(':') in elementNames) {
                    captureDepth = parser.depth
                    current = StringBuilder()
                }
                XmlPullParser.TEXT -> if (captureDepth >= 0) current.append(parser.text)
                XmlPullParser.END_TAG -> if (parser.depth == captureDepth) {
                    current.toString().trim().takeIf { it.isNotEmpty() }?.let(values::add)
                    captureDepth = -1
                }
            }
            parser.next()
        }
        return values
    }

    private fun countXmlElements(bytes: ByteArray?, name: String): Int {
        val parser = newBoundedXmlParser(bytes) ?: return 0
        var count = 0
        while (parser.eventType != XmlPullParser.END_DOCUMENT) {
            if (parser.eventType == XmlPullParser.START_TAG &&
                parser.name.substringAfter(':') == name) {
                count += 1
            }
            parser.next()
        }
        return count
    }

    private fun extractSheetNames(bytes: ByteArray?): List<String> {
        val parser = newBoundedXmlParser(bytes) ?: return emptyList()
        val names = mutableListOf<String>()
        while (parser.eventType != XmlPullParser.END_DOCUMENT && names.size < 100) {
            if (parser.eventType == XmlPullParser.START_TAG &&
                parser.name.substringAfter(':') == "sheet") {
                parser.getAttributeValue(null, "name")?.let(names::add)
            }
            parser.next()
        }
        return names
    }

    private fun extractSharedStrings(bytes: ByteArray?): List<String> {
        val parser = newBoundedXmlParser(bytes) ?: return emptyList()
        val values = mutableListOf<String>()
        var inItem = false
        var inText = false
        var current = StringBuilder()
        while (parser.eventType != XmlPullParser.END_DOCUMENT && values.size < 20_000) {
            when (parser.eventType) {
                XmlPullParser.START_TAG -> when (parser.name.substringAfter(':')) {
                    "si" -> {
                        inItem = true
                        current = StringBuilder()
                    }
                    "t" -> if (inItem) inText = true
                }
                XmlPullParser.TEXT -> if (inText) current.append(parser.text)
                XmlPullParser.END_TAG -> when (parser.name.substringAfter(':')) {
                    "t" -> inText = false
                    "si" -> {
                        values += current.toString()
                        inItem = false
                    }
                }
            }
            parser.next()
        }
        return values
    }

    private fun extractSheetRows(
        bytes: ByteArray?,
        sharedStrings: List<String>,
    ): List<List<String>> {
        val parser = newBoundedXmlParser(bytes) ?: return emptyList()
        val rows = mutableListOf<List<String>>()
        var row: MutableList<String>? = null
        var cellType: String? = null
        var capture = false
        var value = StringBuilder()
        while (parser.eventType != XmlPullParser.END_DOCUMENT && rows.size < 20) {
            when (parser.eventType) {
                XmlPullParser.START_TAG -> when (parser.name.substringAfter(':')) {
                    "row" -> row = mutableListOf()
                    "c" -> {
                        cellType = parser.getAttributeValue(null, "t")
                        value = StringBuilder()
                    }
                    "v", "t" -> capture = row != null
                }
                XmlPullParser.TEXT -> if (capture) value.append(parser.text)
                XmlPullParser.END_TAG -> when (parser.name.substringAfter(':')) {
                    "v", "t" -> capture = false
                    "c" -> {
                        val raw = value.toString().trim()
                        val rendered = if (cellType == "s") {
                            raw.toIntOrNull()?.let { sharedStrings.getOrNull(it) }.orEmpty()
                        } else {
                            raw
                        }
                        row?.takeIf { it.size < 10 }?.add(rendered.take(300))
                    }
                    "row" -> {
                        row?.let { rows += it.toList() }
                        row = null
                    }
                }
            }
            parser.next()
        }
        return rows
    }

    private fun officePartNumber(name: String): Int =
        Regex("(\\d+)").findAll(name).lastOrNull()?.value?.toIntOrNull() ?: Int.MAX_VALUE

    @Suppress("DEPRECATION")
    private fun inspectApk(call: MethodCall, result: MethodChannel.Result) {
        val uri = contentUri(call)
        if (uri == null) {
            result.error("invalid_apk_request", "A content URI is required.", null)
            return
        }
        runReadTask(result, "apk_inspection_failed") {
            val temporary = copyToInspectionCache(uri, ".apk", MAX_APK_INSPECTION_BYTES)
            try {
                val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                    PackageManager.GET_SIGNING_CERTIFICATES
                } else {
                    PackageManager.GET_SIGNATURES
                }
                val info = applicationContext.packageManager.getPackageArchiveInfo(
                    temporary.absolutePath,
                    flags,
                ) ?: throw IllegalArgumentException("The APK package metadata is invalid.")
                val appInfo = info.applicationInfo
                appInfo?.sourceDir = temporary.absolutePath
                appInfo?.publicSourceDir = temporary.absolutePath
                val icon = appInfo?.loadIcon(applicationContext.packageManager)
                val signaturesPresent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                    info.signingInfo?.let {
                        it.apkContentsSigners.isNotEmpty() || it.signingCertificateHistory.isNotEmpty()
                    } == true
                } else {
                    info.signatures?.isNotEmpty() == true
                }
                val installed = try {
                    applicationContext.packageManager.getPackageInfo(info.packageName, 0)
                    true
                } catch (_: PackageManager.NameNotFoundException) {
                    false
                }
                mapOf(
                    "applicationName" to (
                        appInfo?.loadLabel(applicationContext.packageManager)?.toString()
                            ?: info.packageName
                        ),
                    "packageName" to info.packageName,
                    "versionName" to (info.versionName ?: ""),
                    "versionCode" to if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                        info.longVersionCode
                    } else {
                        info.versionCode.toLong()
                    },
                    "signed" to signaturesPresent,
                    "installed" to installed,
                    "iconBytes" to icon?.let(::drawablePng),
                )
            } finally {
                temporary.delete()
            }
        }
    }

    private fun getPdfInfo(call: MethodCall, result: MethodChannel.Result) {
        val uri = contentUri(call)
        if (uri == null) {
            result.error("invalid_pdf_request", "A content URI is required.", null)
            return
        }
        runReadTask(result, "pdf_info_failed") {
            applicationContext.contentResolver.openFileDescriptor(uri, "r")?.use { descriptor ->
                PdfRenderer(descriptor).use { renderer ->
                    mapOf("pageCount" to renderer.pageCount)
                }
            } ?: throw IllegalArgumentException("The PDF could not be opened.")
        }
    }

    private fun renderPdfPage(call: MethodCall, result: MethodChannel.Result) {
        val arguments = call.arguments as? Map<*, *>
        val uri = contentUri(call)
        val pageIndex = (arguments?.get("pageIndex") as? Number)?.toInt() ?: -1
        val maxWidth = (arguments?.get("maxWidth") as? Number)?.toInt() ?: 0
        val maxHeight = (arguments?.get("maxHeight") as? Number)?.toInt() ?: 0
        if (
            uri == null ||
            pageIndex < 0 ||
            maxWidth !in 1..MAX_PDF_DIMENSION ||
            maxHeight !in 1..MAX_PDF_DIMENSION
        ) {
            result.error("invalid_pdf_request", "A bounded PDF page request is required.", null)
            return
        }
        runReadTask(result, "pdf_render_failed") {
            applicationContext.contentResolver.openFileDescriptor(uri, "r")?.use { descriptor ->
                PdfRenderer(descriptor).use { renderer ->
                    require(pageIndex < renderer.pageCount) { "The PDF page is out of range." }
                    renderer.openPage(pageIndex).use { page ->
                        val scale = minOf(
                            maxWidth.toDouble() / page.width,
                            maxHeight.toDouble() / page.height,
                        )
                        val width = (page.width * scale).toInt().coerceAtLeast(1)
                        val height = (page.height * scale).toInt().coerceAtLeast(1)
                        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
                        try {
                            bitmap.eraseColor(android.graphics.Color.WHITE)
                            page.render(
                                bitmap,
                                null,
                                null,
                                PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY,
                            )
                            encodeWithinBudget(bitmap, MAX_PREVIEW_BYTES)
                                ?: throw IllegalArgumentException("The rendered page is too large.")
                        } finally {
                            bitmap.recycle()
                        }
                    }
                }
            } ?: throw IllegalArgumentException("The PDF could not be opened.")
        }
    }

    private fun copyToInspectionCache(uri: Uri, extension: String, maxBytes: Long): File {
        val target = File(applicationContext.cacheDir, "inspect-${UUID.randomUUID()}$extension")
        var copied = 0L
        try {
            applicationContext.contentResolver.openInputStream(uri)?.use { input ->
                FileOutputStream(target).use { output ->
                    val buffer = ByteArray(64 * 1024)
                    while (true) {
                        val count = input.read(buffer)
                        if (count < 0) break
                        copied += count
                        require(copied <= maxBytes) { "The item exceeds the inspection limit." }
                        output.write(buffer, 0, count)
                    }
                }
            } ?: throw IllegalArgumentException("The item could not be opened.")
            return target
        } catch (error: Exception) {
            target.delete()
            throw error
        }
    }

    private fun drawablePng(drawable: Drawable): ByteArray {
        val bitmap = if (drawable is BitmapDrawable && drawable.bitmap != null) {
            drawable.bitmap
        } else {
            val width = drawable.intrinsicWidth.coerceIn(1, 256)
            val height = drawable.intrinsicHeight.coerceIn(1, 256)
            Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888).also { target ->
                val canvas = Canvas(target)
                drawable.setBounds(0, 0, canvas.width, canvas.height)
                drawable.draw(canvas)
            }
        }
        return ByteArrayOutputStream().use { output ->
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, output)
            output.toByteArray()
        }
    }

    private fun requestMediaPermissions(result: MethodChannel.Result) {
        val activity = activityBinding?.activity
        if (activity == null) {
            result.error("activity_unavailable", "A visible activity is required.", null)
            return
        }
        if (pendingPermissionResult != null) {
            result.error("request_in_progress", "A media permission request is already open.", null)
            return
        }
        val permissions = when {
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE -> arrayOf(
                Manifest.permission.READ_MEDIA_IMAGES,
                Manifest.permission.READ_MEDIA_VIDEO,
                Manifest.permission.READ_MEDIA_AUDIO,
                Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED,
            )
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU -> arrayOf(
                Manifest.permission.READ_MEDIA_IMAGES,
                Manifest.permission.READ_MEDIA_VIDEO,
                Manifest.permission.READ_MEDIA_AUDIO,
            )
            else -> arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE)
        }
        val current = mediaPermissionState()
        if (hasRequestedMediaAccess(Build.VERSION.SDK_INT, current)) {
            result.success(current)
            return
        }
        pendingPermissionResult = result
        activity.requestPermissions(permissions, MEDIA_PERMISSION_REQUEST)
    }

    private fun pickDocumentTree(result: MethodChannel.Result) {
        val activity = activityBinding?.activity
        if (activity == null) {
            result.error("activity_unavailable", "A visible activity is required.", null)
            return
        }
        if (pendingTreeResult != null) {
            result.error("request_in_progress", "A directory picker is already open.", null)
            return
        }
        pendingTreeResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION,
            )
        }
        activity.startActivityForResult(intent, DOCUMENT_TREE_REQUEST)
    }

    private fun openContentUri(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val activity = activityBinding?.activity
        val rawUri = call.argument<String>("contentUri")
        val uri = rawUri?.let(Uri::parse)
        if (activity == null || uri?.scheme != ContentResolver.SCHEME_CONTENT) {
            result.success(false)
            return
        }
        val mimeType = applicationContext.contentResolver.getType(uri)
            ?: if (rawUri?.endsWith(".apk", ignoreCase = true) == true) {
                "application/vnd.android.package-archive"
            } else {
                "application/octet-stream"
            }
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, mimeType)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        try {
            activity.startActivity(intent)
            result.success(true)
        } catch (_: Exception) {
            result.success(false)
        }
    }

    private fun queryMediaPage(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val arguments = call.arguments as? Map<*, *>
        val kind = arguments?.get("kind") as? String
        val limit = (arguments?.get("limit") as? Number)?.toInt() ?: 100
        val offset = (arguments?.get("offset") as? Number)?.toInt() ?: 0
        val modifiedAfter = (arguments?.get("modifiedAfterEpochSeconds") as? Number)?.toLong()
        if (kind == null || limit !in 1..250 || offset < 0) {
            result.error("invalid_query", "A bounded media query is required.", null)
            return
        }

        val worker = executor
        if (worker == null || worker.isShutdown) {
            result.error("bridge_unavailable", "The Android bridge is detached.", null)
            return
        }

        worker.execute {
            try {
                val page = readMediaPage(kind, limit, offset, modifiedAfter)
                mainHandler.post { result.success(page) }
            } catch (_: SecurityException) {
                mainHandler.post {
                    result.error(
                        "permission_denied",
                        "Media permission is required before indexing this collection.",
                        null,
                    )
                }
            } catch (error: IllegalArgumentException) {
                mainHandler.post { result.error("invalid_query", error.message, null) }
            } catch (_: Exception) {
                mainHandler.post {
                    result.error(
                        "media_query_failed",
                        "Android could not read this media metadata page.",
                        null,
                    )
                }
            }
        }
    }

    private fun countMedia(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val kind = (call.arguments as? Map<*, *>)?.get("kind") as? String
        if (kind == null) {
            result.error("invalid_query", "A media collection is required.", null)
            return
        }
        val worker = executor
        if (worker == null || worker.isShutdown) {
            result.error("bridge_unavailable", "The Android bridge is detached.", null)
            return
        }
        worker.execute {
            try {
                val target = queryTarget(kind)
                val selection = target.selections.takeIf { it.isNotEmpty() }?.joinToString(" AND ")
                val selectionArgs = target.selectionArguments.takeIf { it.isNotEmpty() }?.toTypedArray()
                val count = applicationContext.contentResolver.query(
                    target.uri,
                    arrayOf(MediaStore.MediaColumns._ID),
                    selection,
                    selectionArgs,
                    null,
                )?.use { it.count } ?: 0
                mainHandler.post { result.success(count) }
            } catch (_: SecurityException) {
                mainHandler.post {
                    result.error(
                        "permission_denied",
                        "Media permission is required before counting this collection.",
                        null,
                    )
                }
            } catch (error: IllegalArgumentException) {
                mainHandler.post { result.error("invalid_query", error.message, null) }
            } catch (_: Exception) {
                mainHandler.post {
                    result.error(
                        "media_query_failed",
                        "Android could not count this media collection.",
                        null,
                    )
                }
            }
        }
    }

    private fun loadBoundedThumbnail(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val arguments = call.arguments as? Map<*, *>
        val rawUri = arguments?.get("contentUri") as? String
        val uri = rawUri?.let(Uri::parse)
        val maxWidth = (arguments?.get("maxWidth") as? Number)?.toInt() ?: 0
        val maxHeight = (arguments?.get("maxHeight") as? Number)?.toInt() ?: 0
        val maxBytes = (arguments?.get("maxBytes") as? Number)?.toInt() ?: 0
        if (
            uri?.scheme != ContentResolver.SCHEME_CONTENT ||
            maxWidth !in 1..MAX_THUMBNAIL_DIMENSION ||
            maxHeight !in 1..MAX_THUMBNAIL_DIMENSION ||
            maxBytes !in MIN_THUMBNAIL_BYTES..MAX_THUMBNAIL_BYTES
        ) {
            result.error(
                "invalid_thumbnail_request",
                "A content URI and strict thumbnail bounds are required.",
                null,
            )
            return
        }
        val worker = executor
        if (worker == null || worker.isShutdown) {
            result.error("bridge_unavailable", "The Android bridge is detached.", null)
            return
        }
        worker.execute {
            try {
                val bytes = readBoundedThumbnail(uri, maxWidth, maxHeight, maxBytes)
                mainHandler.post { result.success(bytes) }
            } catch (_: SecurityException) {
                mainHandler.post {
                    result.error(
                        "permission_denied",
                        "Media permission is required before loading this thumbnail.",
                        null,
                    )
                }
            } catch (_: Exception) {
                mainHandler.post {
                    result.error(
                        "thumbnail_failed",
                        "Android could not load this bounded thumbnail.",
                        null,
                    )
                }
            }
        }
    }

    private fun readBoundedThumbnail(
        uri: Uri,
        maxWidth: Int,
        maxHeight: Int,
        maxBytes: Int,
    ): ByteArray? {
        val resolver = applicationContext.contentResolver
        val decoded = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            resolver.loadThumbnail(uri, Size(maxWidth, maxHeight), null)
        } else {
            decodeSampledBitmap(resolver, uri, maxWidth, maxHeight)
        }
        val bounded = scaleToFit(decoded, maxWidth, maxHeight)
        if (bounded !== decoded) decoded?.recycle()
        return try {
            encodeWithinBudget(bounded, maxBytes)
        } finally {
            bounded.recycle()
        }
    }

    private fun decodeSampledBitmap(
        resolver: ContentResolver,
        uri: Uri,
        maxWidth: Int,
        maxHeight: Int,
    ): Bitmap? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        resolver.openInputStream(uri)?.use { stream ->
            BitmapFactory.decodeStream(stream, null, bounds)
        }
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
        val options = BitmapFactory.Options().apply {
            inSampleSize = sampleSize(bounds.outWidth, bounds.outHeight, maxWidth, maxHeight)
        }
        return resolver.openInputStream(uri)?.use { stream ->
            BitmapFactory.decodeStream(stream, null, options)
        }
    }

    private fun sampleSize(
        width: Int,
        height: Int,
        maxWidth: Int,
        maxHeight: Int,
    ): Int {
        var sample = 1
        while (width / (sample * 2) >= maxWidth || height / (sample * 2) >= maxHeight) {
            sample *= 2
        }
        return sample
    }

    private fun scaleToFit(
        bitmap: Bitmap?,
        maxWidth: Int,
        maxHeight: Int,
    ): Bitmap {
        requireNotNull(bitmap) { "Media item did not expose a thumbnail." }
        if (bitmap.width <= maxWidth && bitmap.height <= maxHeight) return bitmap
        val scale = minOf(maxWidth.toDouble() / bitmap.width, maxHeight.toDouble() / bitmap.height)
        val width = (bitmap.width * scale).toInt().coerceAtLeast(1)
        val height = (bitmap.height * scale).toInt().coerceAtLeast(1)
        return Bitmap.createScaledBitmap(bitmap, width, height, true)
    }

    private fun encodeWithinBudget(
        bitmap: Bitmap,
        maxBytes: Int,
    ): ByteArray? {
        var current = bitmap
        var ownsCurrent = false
        try {
            repeat(5) { attempt ->
                val output = ByteArrayOutputStream()
                val quality = 86 - (attempt * 12)
                if (current.compress(Bitmap.CompressFormat.JPEG, quality, output)) {
                    val bytes = output.toByteArray()
                    if (bytes.size <= maxBytes) return bytes
                }
                val nextWidth = (current.width * 0.75).toInt().coerceAtLeast(1)
                val nextHeight = (current.height * 0.75).toInt().coerceAtLeast(1)
                if (nextWidth == current.width && nextHeight == current.height) return null
                val next = Bitmap.createScaledBitmap(current, nextWidth, nextHeight, true)
                if (ownsCurrent) current.recycle()
                current = next
                ownsCurrent = true
            }
            return null
        } finally {
            if (ownsCurrent) current.recycle()
        }
    }

    private fun readMediaPage(
        kind: String,
        limit: Int,
        offset: Int,
        modifiedAfter: Long?,
    ): Map<String, Any> {
        val target = queryTarget(kind)
        val projection = mutableListOf(
            MediaStore.MediaColumns._ID,
            MediaStore.MediaColumns.DISPLAY_NAME,
            MediaStore.MediaColumns.MIME_TYPE,
            MediaStore.MediaColumns.SIZE,
            MediaStore.MediaColumns.DATE_MODIFIED,
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            projection += MediaStore.MediaColumns.RELATIVE_PATH
            projection += MediaStore.MediaColumns.OWNER_PACKAGE_NAME
        }
        val hasImageColumns = kind == "images" || kind == "photos" || kind == "screenshots"
        val hasDurationColumn = kind == "videos" || kind == "audio"
        if (hasImageColumns) {
            projection += MediaStore.Images.ImageColumns.BUCKET_DISPLAY_NAME
            projection += MediaStore.Images.ImageColumns.DATE_TAKEN
        }
        if (hasDurationColumn) projection += MediaStore.MediaColumns.DURATION

        val selections = target.selections.toMutableList()
        val selectionArguments = target.selectionArguments.toMutableList()
        if (modifiedAfter != null) {
            selections += "${MediaStore.MediaColumns.DATE_MODIFIED} > ?"
            selectionArguments += modifiedAfter.toString()
        }
        val selection = selections.takeIf { it.isNotEmpty() }?.joinToString(" AND ")
        val selectionArgs = selectionArguments.takeIf { it.isNotEmpty() }?.toTypedArray()
        val sortOrder = mediaSortOrder(hasImageColumns)
        val cursor = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val queryArgs = Bundle().apply {
                putString(ContentResolver.QUERY_ARG_SQL_SELECTION, selection)
                putStringArray(ContentResolver.QUERY_ARG_SQL_SELECTION_ARGS, selectionArgs)
                putString(ContentResolver.QUERY_ARG_SQL_SORT_ORDER, sortOrder)
                putInt(ContentResolver.QUERY_ARG_LIMIT, limit + 1)
                putInt(ContentResolver.QUERY_ARG_OFFSET, offset)
            }
            applicationContext.contentResolver.query(
                target.uri,
                projection.toTypedArray(),
                queryArgs,
                null,
            )
        } else {
            applicationContext.contentResolver.query(
                target.uri,
                projection.toTypedArray(),
                selection,
                selectionArgs,
                "$sortOrder LIMIT ${limit + 1} OFFSET $offset",
            )
        } ?: return mapOf("items" to emptyList<Map<String, Any?>>(), "offset" to offset, "hasMore" to false)

        cursor.use {
            val idColumn = it.getColumnIndexOrThrow(MediaStore.MediaColumns._ID)
            val nameColumn = it.getColumnIndexOrThrow(MediaStore.MediaColumns.DISPLAY_NAME)
            val mimeColumn = it.getColumnIndexOrThrow(MediaStore.MediaColumns.MIME_TYPE)
            val sizeColumn = it.getColumnIndexOrThrow(MediaStore.MediaColumns.SIZE)
            val modifiedColumn = it.getColumnIndexOrThrow(MediaStore.MediaColumns.DATE_MODIFIED)
            val relativePathColumn = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                it.getColumnIndex(MediaStore.MediaColumns.RELATIVE_PATH)
            } else {
                -1
            }
            val ownerPackageColumn = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                it.getColumnIndex(MediaStore.MediaColumns.OWNER_PACKAGE_NAME)
            } else {
                -1
            }
            val bucketColumn = if (hasImageColumns) {
                it.getColumnIndex(MediaStore.Images.ImageColumns.BUCKET_DISPLAY_NAME)
            } else {
                -1
            }
            val dateTakenColumn = if (hasImageColumns) {
                it.getColumnIndex(MediaStore.Images.ImageColumns.DATE_TAKEN)
            } else {
                -1
            }
            val durationColumn = if (hasDurationColumn) {
                it.getColumnIndex(MediaStore.MediaColumns.DURATION)
            } else {
                -1
            }
            val items = mutableListOf<Map<String, Any?>>()
            var hasMore = false
            while (it.moveToNext()) {
                if (items.size >= limit) {
                    hasMore = true
                    break
                }
                val id = it.getLong(idColumn)
                val relativePath = if (relativePathColumn >= 0) {
                    it.getString(relativePathColumn)
                } else {
                    null
                }
                val ownerPackage = if (ownerPackageColumn >= 0) {
                    it.getString(ownerPackageColumn)?.takeIf(String::isNotBlank)
                } else {
                    null
                }
                val bucket = if (bucketColumn >= 0) {
                    it.getString(bucketColumn)?.takeIf(String::isNotBlank)
                } else {
                    null
                }
                val pathHint = relativePath
                    ?.trim('/')
                    ?.substringAfterLast('/')
                    ?.takeIf(String::isNotBlank)
                val dateTakenMillis = if (dateTakenColumn >= 0) {
                    it.getLong(dateTakenColumn).coerceAtLeast(0L)
                } else {
                    0L
                }
                val modifiedAtEpochSeconds = it.getLong(modifiedColumn).coerceAtLeast(0L)
                val createdAtEpochSeconds = if (dateTakenMillis > 0) {
                    dateTakenMillis / 1000L
                } else {
                    modifiedAtEpochSeconds
                }
                items += mapOf(
                    "id" to "$kind:$id",
                    "contentUri" to ContentUris.withAppendedId(target.uri, id).toString(),
                    "displayName" to (it.getString(nameColumn) ?: "Unnamed item"),
                    "mimeType" to it.getString(mimeColumn),
                    "sizeBytes" to it.getLong(sizeColumn).coerceAtLeast(0L),
                    "createdAtEpochSeconds" to createdAtEpochSeconds,
                    "modifiedAtEpochSeconds" to modifiedAtEpochSeconds,
                    "relativePath" to relativePath,
                    "sourceHint" to mediaSourceHint(ownerPackage, bucket, pathHint),
                    "durationMillis" to if (durationColumn >= 0 && !it.isNull(durationColumn)) {
                        it.getLong(durationColumn).coerceAtLeast(0L)
                    } else {
                        null
                    },
                )
            }
            return mapOf("items" to items, "offset" to offset, "hasMore" to hasMore)
        }
    }

    private fun queryTarget(kind: String): QueryTarget {
        val externalFiles = MediaStore.Files.getContentUri("external")
        return when (kind) {
            "images", "photos" -> QueryTarget(MediaStore.Images.Media.EXTERNAL_CONTENT_URI)
            "videos" -> QueryTarget(MediaStore.Video.Media.EXTERNAL_CONTENT_URI)
            "audio" -> QueryTarget(MediaStore.Audio.Media.EXTERNAL_CONTENT_URI)
            "screenshots" -> {
                val pathClause = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    "${MediaStore.MediaColumns.RELATIVE_PATH} LIKE ? OR "
                } else {
                    ""
                }
                val arguments = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    listOf("%Screenshots%", "%Screenshot%")
                } else {
                    listOf("%Screenshot%")
                }
                QueryTarget(
                    MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                    listOf("($pathClause${MediaStore.MediaColumns.DISPLAY_NAME} LIKE ?)"),
                    arguments,
                )
            }
            "downloads" -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                QueryTarget(MediaStore.Downloads.EXTERNAL_CONTENT_URI)
            } else {
                QueryTarget(
                    externalFiles,
                    listOf("${MediaStore.MediaColumns.DISPLAY_NAME} IS NOT NULL"),
                )
            }
            "documents" -> QueryTarget(
                externalFiles,
                listOf("${MediaStore.Files.FileColumns.MEDIA_TYPE} = ?"),
                listOf(MediaStore.Files.FileColumns.MEDIA_TYPE_NONE.toString()),
            )
            "applications" -> QueryTarget(
                externalFiles,
                listOf(
                    "(${MediaStore.MediaColumns.MIME_TYPE} = ? OR ${MediaStore.MediaColumns.DISPLAY_NAME} LIKE ?)",
                ),
                listOf("application/vnd.android.package-archive", "%.apk"),
            )
            "archives" -> QueryTarget(
                externalFiles,
                listOf(
                    "(${MediaStore.MediaColumns.MIME_TYPE} IN (?, ?, ?, ?) OR " +
                        "${MediaStore.MediaColumns.DISPLAY_NAME} LIKE ? OR " +
                        "${MediaStore.MediaColumns.DISPLAY_NAME} LIKE ? OR " +
                        "${MediaStore.MediaColumns.DISPLAY_NAME} LIKE ? OR " +
                        "${MediaStore.MediaColumns.DISPLAY_NAME} LIKE ?)",
                ),
                listOf(
                    "application/zip",
                    "application/x-7z-compressed",
                    "application/vnd.rar",
                    "application/x-tar",
                    "%.zip",
                    "%.7z",
                    "%.rar",
                    "%.tar",
                ),
            )
            else -> throw IllegalArgumentException("Unsupported media collection.")
        }
    }

    private fun mediaPermissionState(): Map<String, Boolean> {
        val legacyGranted = Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU &&
            hasPermission(Manifest.permission.READ_EXTERNAL_STORAGE)
        val images = legacyGranted ||
            (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU && hasPermission(Manifest.permission.READ_MEDIA_IMAGES))
        val videos = legacyGranted ||
            (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU && hasPermission(Manifest.permission.READ_MEDIA_VIDEO))
        val audio = legacyGranted ||
            (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU && hasPermission(Manifest.permission.READ_MEDIA_AUDIO))
        val partial = Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE &&
            hasPermission(Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED)
        return mapOf(
            "images" to images,
            "videos" to videos,
            "audio" to audio,
            "partialVisualAccess" to partial,
        )
    }

    private fun storageSnapshot(): Map<String, Any> {
        val stats = StatFs(Environment.getDataDirectory().absolutePath)
        val permissions = mediaPermissionState()
        return mapOf(
            "totalBytes" to stats.totalBytes,
            "availableBytes" to stats.availableBytes,
            "canInspectSharedMedia" to permissions.values.any { it },
            "canInspectOtherAppPrivateData" to false,
            "canInspectDownloads" to false,
            "isAggregateOnly" to true,
            "canClean" to false,
            "systemRestriction" to "当前Android权限不允许第三方应用直接检查该部分。",
            "limitations" to listOf(
                "系统卷总量不能归因到单个文件、分类或应用。",
                "下载和文档仅在 MediaStore 或用户选择的 SAF 范围内可见。",
                "其他应用私有目录、缓存和受保护系统数据不可检查。",
            ),
        )
    }

    private fun hasPermission(permission: String): Boolean =
        applicationContext.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ): Boolean {
        if (requestCode != MEDIA_PERMISSION_REQUEST) return false
        pendingPermissionResult?.success(mediaPermissionState())
        pendingPermissionResult = null
        return true
    }

    override fun onActivityResult(
        requestCode: Int,
        resultCode: Int,
        data: Intent?,
    ): Boolean {
        if (requestCode == WORKSPACE_TREE_REQUEST) {
            val pending = pendingWorkspaceTreeResult
            pendingWorkspaceTreeResult = null
            if (pending == null) return true
            val uri = data?.data
            if (resultCode != Activity.RESULT_OK || uri == null) {
                pending.success(null)
                return true
            }
            try {
                applicationContext.contentResolver.takePersistableUriPermission(
                    uri,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
                )
            } catch (_: SecurityException) {
                pending.error("permission_not_persisted", "Android did not grant persistent read/write access.", null)
                return true
            }
            runReadTask(pending, "workspace_setup_failed") { workspace.establish(uri) }
            return true
        }
        if (requestCode == WORKSPACE_IMPORT_REQUEST) {
            val pending = pendingWorkspaceImportResult
            pendingWorkspaceImportResult = null
            if (pending == null) return true
            if (resultCode != Activity.RESULT_OK || data == null) {
                pending.success(null)
                return true
            }
            val uris = mutableListOf<Uri>()
            data.clipData?.let { clip ->
                for (index in 0 until clip.itemCount) uris += clip.getItemAt(index).uri
            }
            data.data?.let { if (it !in uris) uris += it }
            if (uris.isEmpty()) {
                pending.success(null)
                return true
            }
            runReadTask(pending, "workspace_import_failed") { workspace.importCopies(uris) }
            return true
        }
        if (requestCode == SYSTEM_TRASH_REQUEST) {
            pendingTrashResult?.success(resultCode == Activity.RESULT_OK)
            pendingTrashResult = null
            return true
        }
        if (requestCode != DOCUMENT_TREE_REQUEST) return false
        val pending = pendingTreeResult
        pendingTreeResult = null
        if (pending == null) return true
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            pending.success(null)
            return true
        }
        try {
            applicationContext.contentResolver.takePersistableUriPermission(
                uri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION,
                )
                readOnlyBrowser.remember(uri)
                pending.success(uri.toString())
        } catch (_: SecurityException) {
            pending.error(
                "permission_not_persisted",
                "Android did not grant persistent read access to this directory.",
                null,
            )
        }
        return true
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
        binding.addRequestPermissionsResultListener(this)
        binding.addActivityResultListener(this)
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        onAttachedToActivity(binding)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        detachActivity()
    }

    override fun onDetachedFromActivity() {
        detachActivity()
    }

    private fun detachActivity() {
        activityBinding?.removeRequestPermissionsResultListener(this)
        activityBinding?.removeActivityResultListener(this)
        activityBinding = null
        pendingPermissionResult?.error(
            "activity_detached",
            "The permission request was interrupted.",
            null,
        )
        pendingPermissionResult = null
        pendingTreeResult?.error(
            "activity_detached",
            "The directory picker was interrupted.",
            null,
        )
        pendingTreeResult = null
        pendingWorkspaceTreeResult?.error(
            "activity_detached",
            "The workspace picker was interrupted.",
            null,
        )
        pendingWorkspaceTreeResult = null
        pendingWorkspaceImportResult?.error(
            "activity_detached",
            "The sample picker was interrupted.",
            null,
        )
        pendingWorkspaceImportResult = null
        pendingTrashResult?.error(
            "activity_detached",
            "The system trash request was interrupted.",
            null,
        )
        pendingTrashResult = null
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        executor?.shutdownNow()
        executor = null
    }

    private data class QueryTarget(
        val uri: Uri,
        val selections: List<String> = emptyList(),
        val selectionArguments: List<String> = emptyList(),
    )

    private companion object {
        const val CHANNEL = "picklogic_android_bridge"
        const val PRIVATE_INDEX_FILENAME = "picklogic-index.sqlite3"
        const val MEDIA_PERMISSION_REQUEST = 4701
        const val DOCUMENT_TREE_REQUEST = 4702
        const val WORKSPACE_TREE_REQUEST = 4703
        const val WORKSPACE_IMPORT_REQUEST = 4704
        const val SYSTEM_TRASH_REQUEST = 4705
        const val MAX_THUMBNAIL_DIMENSION = 512
        const val MIN_THUMBNAIL_BYTES = 1024
        const val MAX_THUMBNAIL_BYTES = 512 * 1024
        const val MAX_PREVIEW_DIMENSION = 4096
        const val MAX_PDF_DIMENSION = 2048
        const val MAX_PREVIEW_BYTES = 8 * 1024 * 1024
        const val MAX_TEXT_CHARACTERS = 256 * 1024
        const val MAX_ARCHIVE_ENTRIES = 1000
        const val MAX_OFFICE_PARTS = 64
        const val MAX_OFFICE_PART_BYTES = 768 * 1024
        const val MAX_OFFICE_TOTAL_BYTES = 6 * 1024 * 1024
        const val MAX_OFFICE_SUMMARY_CHARS = 6000
        const val MAX_APK_INSPECTION_BYTES = 512L * 1024L * 1024L
        const val PREFERENCES_NAME = "picklogic-mobile-preferences"
        const val PDF_PAGE_PREFERENCE_PREFIX = "pdfRecentPage-"
        val GRID_INT_PREFERENCES = setOf("screenshotGridColumns", "photoGridColumns")
        val OFFICE_EXTENSIONS = setOf("doc", "docx", "xls", "xlsx", "ppt", "pptx")
        val LEGACY_OFFICE_EXTENSIONS = setOf("doc", "xls", "ppt")
        val PPT_SLIDE_PATTERN = Regex("ppt/slides/slide\\d+\\.xml")
        val XLSX_SHEET_PATTERN = Regex("xl/worksheets/sheet\\d+\\.xml")
    }
}
