import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picklogic_android_bridge/picklogic_android_bridge.dart';
import 'package:picklogic_android_bridge/picklogic_android_bridge_platform_interface.dart';
import 'package:picklogic_core_models/picklogic_core_models.dart';
import 'package:picklogic_mobile/src/mobile_file_browser.dart';
import 'package:picklogic_mobile/src/mobile_folder_insight.dart';
import 'package:picklogic_mobile/src/mobile_repository.dart';

void main() {
  const engine = AndroidFolderInsightEngine();

  test('common folder conventions produce evidence-based explanations', () {
    final screenshot = engine.explain(
      _observation(
        name: 'Screenshots',
        path: const <String>['Internal storage', 'Pictures', 'Screenshots'],
        files: 8,
        families: const <String, int>{'image': 8},
      ),
    );
    expect(screenshot.role, AndroidFolderRole.screenshots);
    expect(screenshot.riskLevel, RiskLevel.review);
    expect(screenshot.confidence, greaterThanOrEqualTo(0.9));
    expect(
      screenshot.evidence,
      contains(FolderInsightEvidence.standardFolderName),
    );
  });

  test(
    'Android media package path is explained without asserting app label',
    () {
      final insight = engine.explain(
        _observation(
          name: 'Images',
          path: const <String>[
            'Internal storage',
            'Android',
            'media',
            'com.example.reader',
            'Images',
          ],
        ),
      );
      expect(insight.role, AndroidFolderRole.appSharedMedia);
      expect(insight.packageIdentifier, 'com.example.reader');
      expect(
        insight.evidence,
        contains(FolderInsightEvidence.packageIdentifier),
      );
    },
  );

  test('unmatched empty folder remains unknown rather than safe', () {
    final insight = engine.explain(
      _observation(
        name: 'x7_state',
        path: const <String>['Internal storage', 'x7_state'],
      ),
    );
    expect(insight.role, AndroidFolderRole.unknown);
    expect(insight.riskLevel, RiskLevel.unknown);
    expect(insight.unresolved, isTrue);
    expect(insight.evidence, contains(FolderInsightEvidence.emptyFolder));
  });

  test(
    'scanner traverses every synthetic SAF directory and survives failure',
    () async {
      const root = AndroidBrowseRoot(
        treeUri: 'content://test/tree/primary',
        documentUri: 'content://test/document/primary',
        displayName: 'Internal storage',
      );
      final pages = <String, List<AndroidBrowseEntry>>{
        root.documentUri: <AndroidBrowseEntry>[
          _directory('DCIM', root.documentUri),
          _directory('mystery_state', root.documentUri),
        ],
        'content://test/document/DCIM': <AndroidBrowseEntry>[
          _file('camera.jpg', 'content://test/document/DCIM', 'image/jpeg'),
        ],
      };
      final inspected = <String>[];
      final scanner = AndroidFolderInsightScanner(
        loadRoots: () async => const <AndroidBrowseRoot>[root],
        loadSummary: ({required treeUri, required directoryUri}) async {
          inspected.add(directoryUri);
          if (directoryUri.endsWith('mystery_state')) {
            throw StateError('synthetic provider denial');
          }
          final all = pages[directoryUri] ?? const <AndroidBrowseEntry>[];
          final files = all.where((entry) => !entry.directory).toList();
          return AndroidBrowseDirectorySummary(
            treeUri: treeUri,
            directoryUri: directoryUri,
            directoryName: directoryUri.split('/').last,
            directories: all
                .where((entry) => entry.directory)
                .toList(growable: false),
            directFileCount: files.length,
            directFileBytes: files.fold<int>(
              0,
              (total, entry) => total + entry.sizeBytes,
            ),
            mimeFamilyCounts: files.isEmpty
                ? const <String, int>{}
                : const <String, int>{'image': 1},
          );
        },
      );

      final result = await scanner.scan();

      expect(result.complete, isTrue);
      expect(result.insights, hasLength(3));
      expect(result.failures, 1);
      expect(inspected, hasLength(3));
      expect(
        result.insights
            .singleWhere((item) => item.observation.displayName == 'DCIM')
            .role,
        AndroidFolderRole.camera,
      );
      expect(
        result.insights
            .singleWhere(
              (item) => item.observation.displayName == 'mystery_state',
            )
            .riskLevel,
        RiskLevel.unknown,
      );
    },
  );

  testWidgets('folder detail separates facts, inference, and limitations', (
    tester,
  ) async {
    final insight = engine.explain(
      _observation(
        name: 'Unknown_42',
        path: const <String>['内部存储', 'Unknown_42'],
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: const <Locale>[Locale('zh'), Locale('en')],
        localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(body: FolderInsightDetails(insight: insight)),
      ),
    );

    expect(find.text('这是什么'), findsOneWidget);
    expect(find.text('已验证事实'), findsOneWidget);
    expect(find.text('规则推断'), findsOneWidget);
    expect(find.text('无法确认的部分', skipOffstage: false), findsOneWidget);
    expect(
      find.textContaining('不代表它无用或可以删除', skipOffstage: false),
      findsOneWidget,
    );
    expect(find.textContaining('字节'), findsNothing);
  });

  testWidgets('file browser Insight follows the current folder and back path', (
    tester,
  ) async {
    final originalPlatform = PicklogicAndroidBridgePlatform.instance;
    final platform = _ContextFolderPlatform();
    PicklogicAndroidBridgePlatform.instance = platform;
    addTearDown(() {
      PicklogicAndroidBridgePlatform.instance = originalPlatform;
    });
    final repository = AndroidMobileRepository();
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: const <Locale>[Locale('zh'), Locale('en')],
        localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: MobileFileBrowserPage(
          repository: repository,
          initialRoot: _ContextFolderPlatform.root,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('mobile-current-folder-insight')),
      findsOneWidget,
    );
    expect(find.textContaining('当前层：1 个子目录'), findsOneWidget);
    expect(platform.inspectedUris.last, _ContextFolderPlatform.rootUri);

    await tester.tap(find.text('Documents'));
    await tester.pumpAndSettle();
    expect(find.textContaining('文档集合'), findsOneWidget);
    expect(platform.inspectedUris.last, _ContextFolderPlatform.documentsUri);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(platform.inspectedUris.last, _ContextFolderPlatform.rootUri);
    expect(find.text('Documents'), findsOneWidget);

    await tester.tap(find.byKey(const Key('mobile-current-folder-insight')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('folder-insight-details')), findsOneWidget);
    expect(find.text('已验证事实'), findsOneWidget);
  });

  testWidgets('empty storage Insight exposes the authorization action first', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        locale: Locale('zh'),
        supportedLocales: <Locale>[Locale('zh'), Locale('en')],
        localizationsDelegates: <LocalizationsDelegate<dynamic>>[
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: SingleChildScrollView(
            child: AccessibleFolderInsightSection(
              repository: SyntheticMobileRepository(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('选择目录并开始分析'), findsOneWidget);
    expect(find.byKey(const Key('folder-insight-scan')), findsNothing);
    final button = tester.widget<FilledButton>(
      find.byKey(const Key('folder-insight-add-root')),
    );
    expect(button.onPressed, isNotNull);
  });
}

AndroidFolderObservation _observation({
  required String name,
  required List<String> path,
  int files = 0,
  Map<String, int> families = const <String, int>{},
}) => AndroidFolderObservation(
  treeUri: 'content://test/tree',
  documentUri: 'content://test/$name',
  displayName: name,
  pathSegments: path,
  directFileCount: files,
  directDirectoryCount: 0,
  directFileBytes: files * 1024,
  mimeFamilyCounts: families,
);

AndroidBrowseEntry _directory(String name, String parentUri) =>
    AndroidBrowseEntry(
      documentUri: 'content://test/document/$name',
      parentUri: parentUri,
      displayName: name,
      mimeType: 'vnd.android.document/directory',
      directory: true,
      sizeBytes: 0,
      modifiedAt: DateTime.utc(2026, 8, 27),
    );

AndroidBrowseEntry _file(String name, String parentUri, String mimeType) =>
    AndroidBrowseEntry(
      documentUri: '$parentUri/$name',
      parentUri: parentUri,
      displayName: name,
      mimeType: mimeType,
      directory: false,
      sizeBytes: 1024,
      modifiedAt: DateTime.utc(2026, 8, 27),
    );

final class _ContextFolderPlatform extends PicklogicAndroidBridgePlatform {
  static const treeUri = 'content://tree/primary';
  static const rootUri = 'content://tree/primary/document/primary:';
  static const documentsUri =
      'content://tree/primary/document/primary:Documents';
  static const root = AndroidBrowseRoot(
    treeUri: treeUri,
    documentUri: rootUri,
    displayName: '内部存储',
  );

  final List<String> inspectedUris = <String>[];

  AndroidBrowseEntry get documents => AndroidBrowseEntry(
    documentUri: documentsUri,
    parentUri: rootUri,
    displayName: 'Documents',
    mimeType: 'vnd.android.document/directory',
    directory: true,
    sizeBytes: 0,
    modifiedAt: DateTime.utc(2026, 8, 27),
  );

  @override
  Future<List<AndroidBrowseRoot>> getBrowseRoots() async =>
      const <AndroidBrowseRoot>[root];

  @override
  Future<AndroidBrowsePage> listBrowseDirectory({
    required String treeUri,
    String? directoryUri,
    int offset = 0,
    int limit = 200,
  }) async {
    final current = directoryUri ?? rootUri;
    return AndroidBrowsePage(
      treeUri: treeUri,
      directoryUri: current,
      directoryName: current == documentsUri ? 'Documents' : '内部存储',
      items: current == documentsUri
          ? <AndroidBrowseEntry>[
              AndroidBrowseEntry(
                documentUri: '$documentsUri/report.pdf',
                parentUri: documentsUri,
                displayName: 'report.pdf',
                mimeType: 'application/pdf',
                directory: false,
                sizeBytes: 2 * 1024 * 1024,
                modifiedAt: DateTime.utc(2026, 8, 27),
              ),
            ]
          : <AndroidBrowseEntry>[documents],
      offset: offset,
      hasMore: false,
    );
  }

  @override
  Future<AndroidBrowseDirectorySummary> inspectBrowseDirectory({
    required String treeUri,
    String? directoryUri,
  }) async {
    final current = directoryUri ?? rootUri;
    inspectedUris.add(current);
    return AndroidBrowseDirectorySummary(
      treeUri: treeUri,
      directoryUri: current,
      directoryName: current == documentsUri ? 'Documents' : '内部存储',
      directories: current == documentsUri
          ? const <AndroidBrowseEntry>[]
          : <AndroidBrowseEntry>[documents],
      directFileCount: current == documentsUri ? 1 : 0,
      directFileBytes: current == documentsUri ? 2 * 1024 * 1024 : 0,
      mimeFamilyCounts: current == documentsUri
          ? const <String, int>{'document': 1}
          : const <String, int>{},
    );
  }
}
