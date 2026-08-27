import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picklogic_android_bridge/picklogic_android_bridge.dart';
import 'package:picklogic_core_models/picklogic_core_models.dart';
import 'package:picklogic_mobile/src/mobile_folder_insight.dart';

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
      final offsets = <String, List<int>>{};
      final scanner = AndroidFolderInsightScanner(
        loadRoots: () async => const <AndroidBrowseRoot>[root],
        loadPage:
            ({
              required treeUri,
              required directoryUri,
              required offset,
              required limit,
            }) async {
              offsets.putIfAbsent(directoryUri, () => <int>[]).add(offset);
              if (directoryUri.endsWith('mystery_state')) {
                throw StateError('synthetic provider denial');
              }
              final all = pages[directoryUri] ?? const <AndroidBrowseEntry>[];
              final items = all.skip(offset).take(1).toList(growable: false);
              return AndroidBrowsePage(
                treeUri: treeUri,
                directoryUri: directoryUri,
                directoryName: directoryUri.split('/').last,
                items: items,
                offset: offset,
                hasMore: offset + items.length < all.length,
              );
            },
      );

      final result = await scanner.scan();

      expect(result.complete, isTrue);
      expect(result.insights, hasLength(3));
      expect(result.failures, 1);
      expect(offsets[root.documentUri], <int>[0, 1]);
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
