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
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.os.StatFs
import android.provider.MediaStore
import android.util.Size
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.PluginRegistry
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

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
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        applicationContext = binding.applicationContext
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
            "openContentUri" -> openContentUri(call, result)
            else -> result.notImplemented()
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
        val intent = Intent(Intent.ACTION_VIEW, uri).apply {
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
        if (hasImageColumns) {
            projection += MediaStore.Images.ImageColumns.BUCKET_DISPLAY_NAME
            projection += MediaStore.Images.ImageColumns.DATE_TAKEN
        }

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
                    "sourceHint" to (ownerPackage ?: bucket ?: pathHint),
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
        const val MAX_THUMBNAIL_DIMENSION = 512
        const val MIN_THUMBNAIL_BYTES = 1024
        const val MAX_THUMBNAIL_BYTES = 512 * 1024
    }
}
