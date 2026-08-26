package io.picklogic.picklogic_android_bridge

import android.content.ContentResolver
import android.content.Context
import android.net.Uri
import android.provider.DocumentsContract

/**
 * Read-only hierarchical browser for directories explicitly granted through
 * Android's Storage Access Framework. It never requests broad storage access
 * and never calls a mutating DocumentsContract method.
 */
internal class AndroidReadOnlyBrowser(private val context: Context) {
    private val resolver: ContentResolver = context.contentResolver
    private val preferences = context.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)

    fun remember(treeUri: Uri) {
        require(treeUri.scheme == ContentResolver.SCHEME_CONTENT) { "A SAF tree URI is required." }
        val roots = preferences.getStringSet(ROOTS_KEY, emptySet()).orEmpty().toMutableSet()
        roots += treeUri.toString()
        preferences.edit().putStringSet(ROOTS_KEY, roots).apply()
    }

    fun roots(): List<Map<String, Any?>> {
        val granted = resolver.persistedUriPermissions
            .filter { it.isReadPermission }
            .map { it.uri.toString() }
            .toSet()
        val remembered = preferences.getStringSet(ROOTS_KEY, emptySet()).orEmpty()
        val valid = remembered.intersect(granted)
        if (valid.size != remembered.size) {
            preferences.edit().putStringSet(ROOTS_KEY, valid).apply()
        }
        return valid.mapNotNull { raw ->
            runCatching {
                val tree = Uri.parse(raw)
                val root = rootDocumentUri(tree)
                val metadata = queryDocument(tree, root)
                mapOf(
                    "treeUri" to tree.toString(),
                    "documentUri" to root.toString(),
                    "displayName" to (metadata?.displayName?.takeIf(String::isNotBlank) ?: "Storage"),
                )
            }.getOrNull()
        }.sortedBy { (it["displayName"] as String).lowercase() }
    }

    fun list(
        treeUri: Uri,
        directoryUri: Uri?,
        offset: Int,
        limit: Int,
    ): Map<String, Any?> {
        require(offset >= 0) { "Offset must not be negative." }
        require(limit in 1..250) { "Limit must be between 1 and 250." }
        assertRemembered(treeUri)
        val directory = directoryUri ?: rootDocumentUri(treeUri)
        assertWithinTree(treeUri, directory)
        val parentMetadata = queryDocument(treeUri, directory)
            ?: throw IllegalArgumentException("The selected directory is no longer available.")
        require(parentMetadata.directory) { "The selected item is not a directory." }

        val childUri = DocumentsContract.buildChildDocumentsUriUsingTree(
            treeUri,
            DocumentsContract.getDocumentId(directory),
        )
        val all = mutableListOf<DocumentMetadata>()
        resolver.query(childUri, PROJECTION, null, null, null)?.use { cursor ->
            while (cursor.moveToNext()) all += cursorMetadata(treeUri, cursor)
        }
        all.sortWith(
            compareByDescending<DocumentMetadata> { it.directory }
                .thenBy(String.CASE_INSENSITIVE_ORDER) { it.displayName }
                .thenBy { it.displayName },
        )
        val page = all.drop(offset).take(limit)
        return mapOf(
            "treeUri" to treeUri.toString(),
            "directoryUri" to directory.toString(),
            "directoryName" to parentMetadata.displayName,
            "offset" to offset,
            "hasMore" to (offset + page.size < all.size),
            "items" to page.map { metadata ->
                mapOf(
                    "documentUri" to metadata.uri.toString(),
                    "parentUri" to directory.toString(),
                    "displayName" to metadata.displayName,
                    "mimeType" to metadata.mimeType,
                    "directory" to metadata.directory,
                    "sizeBytes" to metadata.sizeBytes,
                    "modifiedAtMillis" to metadata.modifiedAtMillis,
                )
            },
        )
    }

    private fun assertRemembered(treeUri: Uri) {
        val remembered = preferences.getStringSet(ROOTS_KEY, emptySet()).orEmpty()
        val persisted = resolver.persistedUriPermissions.any {
            it.isReadPermission && it.uri == treeUri
        }
        require(treeUri.toString() in remembered && persisted) {
            "This directory is not an active PickLogic read-only root."
        }
    }

    private fun rootDocumentUri(treeUri: Uri): Uri =
        DocumentsContract.buildDocumentUriUsingTree(
            treeUri,
            DocumentsContract.getTreeDocumentId(treeUri),
        )

    private fun assertWithinTree(treeUri: Uri, documentUri: Uri) {
        require(treeUri.authority == documentUri.authority) { "The item is outside the selected tree." }
        val rootId = DocumentsContract.getTreeDocumentId(treeUri)
        val documentId = DocumentsContract.getDocumentId(documentUri)
        require(documentId == rootId || documentId.startsWith("$rootId/")) {
            "The item is outside the selected tree."
        }
    }

    private fun queryDocument(treeUri: Uri, documentUri: Uri): DocumentMetadata? =
        resolver.query(documentUri, PROJECTION, null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) cursorMetadata(treeUri, cursor) else null
        }

    private fun cursorMetadata(treeUri: Uri, cursor: android.database.Cursor): DocumentMetadata {
        val id = cursor.getString(
            cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_DOCUMENT_ID),
        )
        val mimeType = cursor.getString(
            cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_MIME_TYPE),
        ) ?: "application/octet-stream"
        return DocumentMetadata(
            uri = DocumentsContract.buildDocumentUriUsingTree(treeUri, id),
            displayName = cursor.getString(
                cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_DISPLAY_NAME),
            ) ?: "Unnamed item",
            mimeType = mimeType,
            directory = mimeType == DocumentsContract.Document.MIME_TYPE_DIR,
            sizeBytes = cursor.getLongOrZero(DocumentsContract.Document.COLUMN_SIZE),
            modifiedAtMillis = cursor.getLongOrZero(DocumentsContract.Document.COLUMN_LAST_MODIFIED),
        )
    }

    private data class DocumentMetadata(
        val uri: Uri,
        val displayName: String,
        val mimeType: String,
        val directory: Boolean,
        val sizeBytes: Long,
        val modifiedAtMillis: Long,
    )

    private companion object {
        const val PREFERENCES_NAME = "picklogic-mobile-preferences"
        const val ROOTS_KEY = "readOnlyBrowseRoots"
        val PROJECTION = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE,
            DocumentsContract.Document.COLUMN_SIZE,
            DocumentsContract.Document.COLUMN_LAST_MODIFIED,
        )
    }
}

private fun android.database.Cursor.getLongOrZero(column: String): Long {
    val index = getColumnIndex(column)
    return if (index >= 0 && !isNull(index)) getLong(index).coerceAtLeast(0L) else 0L
}
