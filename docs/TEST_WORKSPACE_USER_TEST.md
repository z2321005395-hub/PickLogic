# PickLogic user-test workspace

## Windows Standard / Pro

1. Open `PickLogic-TestWorkspace` from the file toolbar. PickLogic creates it under the current Windows user profile.
2. Select `Import test copies` and choose a few non-sensitive samples. PickLogic copies them into `Inbox`; originals stay unchanged.
3. In the Test Workspace, try New folder, Rename, Move, dual-pane drag, Move to Test-Trash, and Undo.
4. A normal disk or folder is browse-only until you choose `Manage folder` and authorize that exact folder with the Windows picker.
5. Deleting inside a managed folder uses the Windows Recycle Bin. If Windows supplies an undo record, PickLogic can undo it during the current session; otherwise restore it in Explorer.

## Windows Pro literature

1. Open Literature and select `Add PDF`, or drag local PDFs into the import area.
2. The library catalog, metadata edits, and reading position persist locally.
3. Selected PDF text can be copied. Translation remains disabled until a provider is explicitly configured; only selected text is sent.
4. Rename always starts with a preview and is executable only inside the Test Workspace or an explicitly managed folder.

## Android

1. Grant media permission through the Android system prompt to browse media.
2. In Settings, open Test Workspace and choose or create `Documents/PickLogic-TestWorkspace` with the system SAF picker.
3. Use `Import test copies`; operations are limited to that authorized tree. Delete moves a test copy to `Test-Trash`, and Undo restores it when possible.
4. Media deletion uses Android's system Trash confirmation. Screenshot `Delete review` is only a local review marker and never deletes media.

Do not use private filenames or content in bug screenshots or public reports.
