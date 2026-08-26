/// Formats a byte count for user-facing file and storage surfaces.
///
/// PickLogic uses compact binary multiples with familiar KB/MB/GB/TB labels.
/// Raw byte counts are intentionally not shown in the main UI.
String formatFileSize(int bytes) {
  assert(bytes >= 0, 'bytes must not be negative');
  if (bytes <= 0) return '0 KB';
  if (bytes < 1024) return '< 1 KB';

  const kibibyte = 1024;
  const mebibyte = kibibyte * 1024;
  const gibibyte = mebibyte * 1024;
  const tebibyte = gibibyte * 1024;

  if (bytes >= tebibyte) {
    return '${(bytes / tebibyte).toStringAsFixed(1)} TB';
  }
  if (bytes >= gibibyte) {
    return '${(bytes / gibibyte).toStringAsFixed(1)} GB';
  }
  if (bytes >= mebibyte) {
    return '${(bytes / mebibyte).toStringAsFixed(1)} MB';
  }
  return '${(bytes / kibibyte).toStringAsFixed(1)} KB';
}
