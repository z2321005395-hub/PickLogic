import 'dart:io';

final class SqliteNativeAssetSpec {
  const SqliteNativeAssetSpec({
    required this.platform,
    required this.sourceName,
    required this.bundledName,
    required this.sha256,
  });

  final String platform;
  final String sourceName;
  final String bundledName;
  final String sha256;

  Uri get downloadUri => Uri.parse(
    'https://github.com/simolus3/sqlite3.dart/releases/download/'
    'sqlite3-3.5.1/$sourceName',
  );

  String get hookCacheSubdirectory => 'download-${sha256.substring(0, 8)}';
}

const windowsSqlite = SqliteNativeAssetSpec(
  platform: 'windows-x64',
  sourceName: 'sqlite3.x64.windows.dll',
  bundledName: 'sqlite3.dll',
  sha256: 'e6ebc2642223bb419a666e278ae4d2cef586cd528633e1a595270490b51c278a',
);

const linuxSqlite = SqliteNativeAssetSpec(
  platform: 'linux-x64',
  sourceName: 'libsqlite3.x64.linux.so',
  bundledName: 'libsqlite3.so',
  sha256: 'b17729184e5a2818055ecbddd5ed6642521bfe6e56aafa472330e483c0e2e0d2',
);

const androidX64Sqlite = SqliteNativeAssetSpec(
  platform: 'android-x64',
  sourceName: 'libsqlite3.x64.android.so',
  bundledName: 'libsqlite3.so',
  sha256: '949965f0eba976f707ae364cdcb42c342b5f0626081f8d7f0378fb7b52848772',
);

SqliteNativeAssetSpec get hostSqlite =>
    switch ((Platform.isWindows, Platform.isLinux)) {
      (true, false) => windowsSqlite,
      (false, true) => linuxSqlite,
      _ => throw UnsupportedError(
        'The pinned SQLite prefetch supports Windows x64 and Linux x64.',
      ),
    };

SqliteNativeAssetSpec sqliteForTarget(String? target) => switch (target) {
  null || 'host' => hostSqlite,
  'android-x64' => androidX64Sqlite,
  _ => throw UnsupportedError(
    'Unsupported SQLite prefetch target: $target. '
    'Expected host or android-x64.',
  ),
};
