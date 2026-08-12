final class WindowsPathAttributes {
  const WindowsPathAttributes({
    required this.hidden,
    required this.system,
    required this.readOnly,
    required this.directory,
  });

  factory WindowsPathAttributes.fromMap(Map<Object?, Object?> map) =>
      WindowsPathAttributes(
        hidden: map['hidden']! as bool,
        system: map['system']! as bool,
        readOnly: map['readOnly']! as bool,
        directory: map['directory']! as bool,
      );

  final bool hidden;
  final bool system;
  final bool readOnly;
  final bool directory;
}

final class WindowsStorageSummary {
  const WindowsStorageSummary({
    required this.root,
    required this.totalBytes,
    required this.availableBytes,
  });

  factory WindowsStorageSummary.fromMap(Map<Object?, Object?> map) =>
      WindowsStorageSummary(
        root: map['root']! as String,
        totalBytes: map['totalBytes']! as int,
        availableBytes: map['availableBytes']! as int,
      );

  final String root;
  final int totalBytes;
  final int availableBytes;
}
