# PickLogic Android Bridge

Narrow Android adapter for MediaStore, SAF, bounded thumbnail decoding, incremental metadata queries, and platform restrictions. It obeys scoped storage and Developer Safe Mode.

Thumbnail requests accept only `content://` locators and enforce both dimensions (maximum 512 x 512) and encoded size (maximum 512 KiB) below the Flutter UI. Media queries remain bounded to 250 metadata rows and support a modification-time checkpoint. No bridge call schedules OCR, mutates media, or claims access to other applications' private storage.
