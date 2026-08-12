package io.picklogic.picklogic_android_bridge

import android.Manifest
import android.app.Activity
import android.content.ContentResolver
import android.content.ContentUris
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.os.StatFs
import android.provider.MediaStore
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.PluginRegistry
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

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
            "queryMediaPage" -> queryMediaPage(call, result)
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
        if (permissions.all(::hasPermission)) {
            result.success(mediaPermissionState())
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
            MediaStore.MediaColumns.DATE_ADDED,
            MediaStore.MediaColumns.DATE_MODIFIED,
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            projection += MediaStore.MediaColumns.RELATIVE_PATH
        }

        val selections = target.selections.toMutableList()
        val selectionArguments = target.selectionArguments.toMutableList()
        if (modifiedAfter != null) {
            selections += "${MediaStore.MediaColumns.DATE_MODIFIED} > ?"
            selectionArguments += modifiedAfter.toString()
        }
        val selection = selections.takeIf { it.isNotEmpty() }?.joinToString(" AND ")
        val selectionArgs = selectionArguments.takeIf { it.isNotEmpty() }?.toTypedArray()
        val cursor = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val queryArgs = Bundle().apply {
                putString(ContentResolver.QUERY_ARG_SQL_SELECTION, selection)
                putStringArray(ContentResolver.QUERY_ARG_SQL_SELECTION_ARGS, selectionArgs)
                putStringArray(
                    ContentResolver.QUERY_ARG_SORT_COLUMNS,
                    arrayOf(MediaStore.MediaColumns.DATE_MODIFIED, MediaStore.MediaColumns._ID),
                )
                putInt(
                    ContentResolver.QUERY_ARG_SORT_DIRECTION,
                    ContentResolver.QUERY_SORT_DIRECTION_DESCENDING,
                )
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
                "${MediaStore.MediaColumns.DATE_MODIFIED} DESC, " +
                    "${MediaStore.MediaColumns._ID} DESC LIMIT ${limit + 1} OFFSET $offset",
            )
        } ?: return mapOf("items" to emptyList<Map<String, Any?>>(), "offset" to offset, "hasMore" to false)

        cursor.use {
            val idColumn = it.getColumnIndexOrThrow(MediaStore.MediaColumns._ID)
            val nameColumn = it.getColumnIndexOrThrow(MediaStore.MediaColumns.DISPLAY_NAME)
            val mimeColumn = it.getColumnIndexOrThrow(MediaStore.MediaColumns.MIME_TYPE)
            val sizeColumn = it.getColumnIndexOrThrow(MediaStore.MediaColumns.SIZE)
            val addedColumn = it.getColumnIndexOrThrow(MediaStore.MediaColumns.DATE_ADDED)
            val modifiedColumn = it.getColumnIndexOrThrow(MediaStore.MediaColumns.DATE_MODIFIED)
            val relativePathColumn = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                it.getColumnIndex(MediaStore.MediaColumns.RELATIVE_PATH)
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
                items += mapOf(
                    "id" to "$kind:$id",
                    "contentUri" to ContentUris.withAppendedId(target.uri, id).toString(),
                    "displayName" to (it.getString(nameColumn) ?: "Unnamed item"),
                    "mimeType" to it.getString(mimeColumn),
                    "sizeBytes" to it.getLong(sizeColumn).coerceAtLeast(0L),
                    "createdAtEpochSeconds" to it.getLong(addedColumn).coerceAtLeast(0L),
                    "modifiedAtEpochSeconds" to it.getLong(modifiedColumn).coerceAtLeast(0L),
                    "relativePath" to if (relativePathColumn >= 0) it.getString(relativePathColumn) else null,
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
            "systemRestriction" to "当前Android权限不允许第三方应用直接检查该部分。",
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
        const val MEDIA_PERMISSION_REQUEST = 4701
        const val DOCUMENT_TREE_REQUEST = 4702
    }
}
