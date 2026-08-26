package io.picklogic.picklogic_android_bridge

import android.content.ContentResolver
import android.content.Context
import android.net.Uri
import android.provider.DocumentsContract
import java.util.ArrayDeque
import java.util.UUID

/** SAF-only mutable workspace. Every operation is constrained to one persisted tree. */
internal class AndroidWorkspaceManager(private val context: Context) {
    private val resolver: ContentResolver = context.contentResolver
    private val preferences = context.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)
    private val undo = linkedMapOf<String, WorkspaceUndo>()

    fun establish(treeUri: Uri): Map<String, Any?> {
        require(treeUri.scheme == ContentResolver.SCHEME_CONTENT) { "A SAF tree URI is required." }
        preferences.edit().putString(TREE_URI_KEY, treeUri.toString()).apply()
        val root = rootDocumentUri(treeUri)
        WORKSPACE_DIRECTORIES.forEach { ensureDirectory(treeUri, root, it) }
        return state()
    }

    fun state(): Map<String, Any?> {
        val tree = persistedTree() ?: return mapOf(
            "authorized" to false,
            "treeUri" to null,
            "entries" to emptyList<Map<String, Any?>>(),
            "undoAvailable" to false,
        )
        val entries = listRecursively(tree)
        return mapOf(
            "authorized" to true,
            "treeUri" to tree.toString(),
            "entries" to entries,
            "undoAvailable" to undo.isNotEmpty(),
        )
    }

    fun importCopies(sourceUris: List<Uri>): Map<String, Any?> {
        val tree = requireTree()
        val root = rootDocumentUri(tree)
        val inbox = ensureDirectory(tree, root, "Inbox")
        sourceUris.take(MAX_IMPORT_ITEMS).forEach { source ->
            require(source.scheme == ContentResolver.SCHEME_CONTENT) { "Only content URIs are accepted." }
            val metadata = queryDocument(source)
            val displayName = metadata?.displayName?.takeIf(String::isNotBlank) ?: "Imported item"
            val mimeType = resolver.getType(source) ?: "application/octet-stream"
            val uniqueName = uniqueName(tree, inbox, displayName)
            val target = DocumentsContract.createDocument(resolver, inbox, mimeType, uniqueName)
                ?: throw IllegalArgumentException("Android could not create the workspace copy.")
            var copied = 0L
            try {
                resolver.openInputStream(source)?.use { input ->
                    resolver.openOutputStream(target, "w")?.use { output ->
                        val buffer = ByteArray(64 * 1024)
                        while (true) {
                            val count = input.read(buffer)
                            if (count < 0) break
                            copied += count
                            require(copied <= MAX_SINGLE_IMPORT_BYTES) {
                                "The selected sample exceeds the workspace copy limit."
                            }
                            output.write(buffer, 0, count)
                        }
                    } ?: throw IllegalArgumentException("The workspace copy could not be written.")
                } ?: throw IllegalArgumentException("The selected sample could not be read.")
            } catch (error: Exception) {
                DocumentsContract.deleteDocument(resolver, target)
                throw error
            }
        }
        return state()
    }

    fun createFolder(parentUri: Uri?, name: String): Map<String, Any?> {
        val tree = requireTree()
        val parent = parentUri ?: rootDocumentUri(tree)
        assertWithinTree(tree, parent)
        val safeName = validateName(name)
        require(findChild(tree, parent, safeName) == null) { "A folder with this name already exists." }
        DocumentsContract.createDocument(
            resolver,
            parent,
            DocumentsContract.Document.MIME_TYPE_DIR,
            safeName,
        ) ?: throw IllegalArgumentException("Android could not create this folder.")
        return state()
    }

    fun rename(documentUri: Uri, name: String): Map<String, Any?> {
        val tree = requireTree()
        assertWithinTree(tree, documentUri)
        require(documentUri != rootDocumentUri(tree)) { "The workspace root cannot be renamed here." }
        val previous = queryDocument(documentUri)
            ?: throw IllegalArgumentException("The workspace item no longer exists.")
        val renamed = DocumentsContract.renameDocument(resolver, documentUri, validateName(name))
            ?: throw IllegalArgumentException("Android could not rename this workspace item.")
        val id = UUID.randomUUID().toString()
        undo[id] = WorkspaceUndo.Rename(currentUri = renamed, previousName = previous.displayName)
        trimUndo()
        return state() + mapOf("operationId" to id)
    }

    fun move(documentUri: Uri, sourceParentUri: Uri, targetParentUri: Uri): Map<String, Any?> {
        val tree = requireTree()
        assertWithinTree(tree, documentUri)
        assertWithinTree(tree, sourceParentUri)
        assertWithinTree(tree, targetParentUri)
        val moved = DocumentsContract.moveDocument(
            resolver,
            documentUri,
            sourceParentUri,
            targetParentUri,
        ) ?: throw IllegalArgumentException("Android could not move this workspace item.")
        val id = UUID.randomUUID().toString()
        undo[id] = WorkspaceUndo.Move(
            currentUri = moved,
            currentParent = targetParentUri,
            previousParent = sourceParentUri,
        )
        trimUndo()
        return state() + mapOf("operationId" to id)
    }

    fun trash(documentUri: Uri, sourceParentUri: Uri): Map<String, Any?> {
        val tree = requireTree()
        val root = rootDocumentUri(tree)
        val trash = ensureDirectory(tree, root, "Test-Trash")
        assertWithinTree(tree, documentUri)
        assertWithinTree(tree, sourceParentUri)
        require(documentUri != trash) { "The Test-Trash folder cannot be trashed." }
        val moved = DocumentsContract.moveDocument(resolver, documentUri, sourceParentUri, trash)
            ?: throw IllegalArgumentException("Android could not move this item to Test-Trash.")
        val id = UUID.randomUUID().toString()
        undo[id] = WorkspaceUndo.Move(
            currentUri = moved,
            currentParent = trash,
            previousParent = sourceParentUri,
        )
        trimUndo()
        return state() + mapOf("operationId" to id)
    }

    fun undo(operationId: String?): Map<String, Any?> {
        val id = operationId ?: undo.keys.lastOrNull()
            ?: throw IllegalArgumentException("There is no workspace operation to undo.")
        val operation = undo.remove(id)
            ?: throw IllegalArgumentException("This undo record is no longer available.")
        when (operation) {
            is WorkspaceUndo.Rename -> {
                DocumentsContract.renameDocument(resolver, operation.currentUri, operation.previousName)
                    ?: throw IllegalArgumentException("Android could not undo this rename.")
            }
            is WorkspaceUndo.Move -> {
                DocumentsContract.moveDocument(
                    resolver,
                    operation.currentUri,
                    operation.currentParent,
                    operation.previousParent,
                ) ?: throw IllegalArgumentException("Android could not undo this move.")
            }
        }
        return state()
    }

    private fun persistedTree(): Uri? = preferences.getString(TREE_URI_KEY, null)?.let(Uri::parse)

    private fun requireTree(): Uri = persistedTree()
        ?: throw IllegalArgumentException("Choose a PickLogic Test Workspace first.")

    private fun rootDocumentUri(tree: Uri): Uri = DocumentsContract.buildDocumentUriUsingTree(
        tree,
        DocumentsContract.getTreeDocumentId(tree),
    )

    private fun ensureDirectory(tree: Uri, parent: Uri, name: String): Uri =
        findChild(tree, parent, name)?.takeIf { it.mimeType == DocumentsContract.Document.MIME_TYPE_DIR }?.uri
            ?: DocumentsContract.createDocument(
                resolver,
                parent,
                DocumentsContract.Document.MIME_TYPE_DIR,
                name,
            )
            ?: throw IllegalArgumentException("Android could not create $name.")

    private fun findChild(tree: Uri, parent: Uri, name: String): DocumentMetadata? {
        val parentId = DocumentsContract.getDocumentId(parent)
        val children = DocumentsContract.buildChildDocumentsUriUsingTree(tree, parentId)
        resolver.query(children, PROJECTION, null, null, null)?.use { cursor ->
            while (cursor.moveToNext()) {
                val metadata = cursorMetadata(tree, cursor)
                if (metadata.displayName.equals(name, ignoreCase = true)) return metadata
            }
        }
        return null
    }

    private fun queryDocument(uri: Uri): DocumentMetadata? = resolver.query(
        uri,
        PROJECTION,
        null,
        null,
        null,
    )?.use { cursor -> if (cursor.moveToFirst()) cursorMetadata(uri, cursor) else null }

    private fun cursorMetadata(treeOrDocumentUri: Uri, cursor: android.database.Cursor): DocumentMetadata {
        val id = cursor.getString(cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_DOCUMENT_ID))
        val tree = persistedTree()
        val uri = if (tree != null) DocumentsContract.buildDocumentUriUsingTree(tree, id) else treeOrDocumentUri
        return DocumentMetadata(
            uri = uri,
            displayName = cursor.getString(
                cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_DISPLAY_NAME),
            ) ?: "Unnamed item",
            mimeType = cursor.getString(
                cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_MIME_TYPE),
            ) ?: "application/octet-stream",
            sizeBytes = cursor.getLongOrZero(DocumentsContract.Document.COLUMN_SIZE),
            modifiedAtMillis = cursor.getLongOrZero(DocumentsContract.Document.COLUMN_LAST_MODIFIED),
        )
    }

    private fun listRecursively(tree: Uri): List<Map<String, Any?>> {
        val root = rootDocumentUri(tree)
        val queue = ArrayDeque<Pair<Uri, Int>>()
        queue.add(root to 0)
        val result = mutableListOf<Map<String, Any?>>()
        while (queue.isNotEmpty() && result.size < MAX_LISTED_ENTRIES) {
            val (parent, depth) = queue.removeFirst()
            if (depth > MAX_DEPTH) continue
            val children = DocumentsContract.buildChildDocumentsUriUsingTree(
                tree,
                DocumentsContract.getDocumentId(parent),
            )
            resolver.query(children, PROJECTION, null, null, null)?.use { cursor ->
                while (cursor.moveToNext() && result.size < MAX_LISTED_ENTRIES) {
                    val metadata = cursorMetadata(tree, cursor)
                    val directory = metadata.mimeType == DocumentsContract.Document.MIME_TYPE_DIR
                    result += mapOf(
                        "documentUri" to metadata.uri.toString(),
                        "parentUri" to parent.toString(),
                        "displayName" to metadata.displayName,
                        "mimeType" to metadata.mimeType,
                        "directory" to directory,
                        "sizeBytes" to metadata.sizeBytes,
                        "modifiedAtMillis" to metadata.modifiedAtMillis,
                        "depth" to depth,
                    )
                    if (directory) queue.add(metadata.uri to depth + 1)
                }
            }
        }
        return result
    }

    private fun assertWithinTree(tree: Uri, documentUri: Uri) {
        require(tree.authority == documentUri.authority) { "The item is outside the authorized tree." }
        val rootId = DocumentsContract.getTreeDocumentId(tree)
        val documentId = DocumentsContract.getDocumentId(documentUri)
        require(documentId == rootId || documentId.startsWith("$rootId/")) {
            "The item is outside the authorized tree."
        }
    }

    private fun validateName(value: String): String {
        val name = value.trim()
        require(name.isNotEmpty() && name.length <= 160) { "Enter a name up to 160 characters." }
        require('/' !in name && '\\' !in name && name != "." && name != "..") {
            "The name contains an invalid path separator."
        }
        return name
    }

    private fun uniqueName(tree: Uri, parent: Uri, original: String): String {
        if (findChild(tree, parent, original) == null) return original
        val dot = original.lastIndexOf('.')
        val base = if (dot > 0) original.substring(0, dot) else original
        val extension = if (dot > 0) original.substring(dot) else ""
        for (index in 2..999) {
            val candidate = "$base ($index)$extension"
            if (findChild(tree, parent, candidate) == null) return candidate
        }
        return "$base-${UUID.randomUUID()}$extension"
    }

    private fun trimUndo() {
        while (undo.size > MAX_UNDO_RECORDS) undo.remove(undo.keys.first())
    }

    private data class DocumentMetadata(
        val uri: Uri,
        val displayName: String,
        val mimeType: String,
        val sizeBytes: Long,
        val modifiedAtMillis: Long,
    )

    private sealed interface WorkspaceUndo {
        data class Rename(val currentUri: Uri, val previousName: String) : WorkspaceUndo
        data class Move(
            val currentUri: Uri,
            val currentParent: Uri,
            val previousParent: Uri,
        ) : WorkspaceUndo
    }

    private companion object {
        const val PREFERENCES_NAME = "picklogic-mobile-preferences"
        const val TREE_URI_KEY = "testWorkspaceTreeUri"
        const val MAX_IMPORT_ITEMS = 24
        const val MAX_SINGLE_IMPORT_BYTES = 512L * 1024L * 1024L
        const val MAX_LISTED_ENTRIES = 800
        const val MAX_DEPTH = 8
        const val MAX_UNDO_RECORDS = 20
        val WORKSPACE_DIRECTORIES = listOf(
            "Inbox",
            "Documents",
            "Images",
            "Videos",
            "Audio",
            "PDFs",
            "Archives",
            "Test-Trash",
            "Restore",
        )
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
