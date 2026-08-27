import 'package:picklogic_core_models/picklogic_core_models.dart';
import 'package:picklogic_insight_engine/picklogic_insight_engine.dart';
import 'package:test/test.dart';

void main() {
  const engine = FolderInsightEngine();

  test('Android app media identifies package ownership from path evidence', () {
    final insight = engine.explain(
      _observation(
        platform: PickLogicPlatform.android,
        name: 'Images',
        path: const [
          'Internal storage',
          'Android',
          'media',
          'org.example.reader',
          'Images',
        ],
      ),
    );
    expect(insight.role, FolderRole.appSharedMedia);
    expect(insight.probableOwner, 'org.example.reader');
    expect(insight.evidence, contains(FolderEvidence.packageIdentifier));
  });

  test(
    'Windows AppData child is explained without declaring it disposable',
    () {
      final insight = engine.explain(
        _observation(
          platform: PickLogicPlatform.windows,
          name: 'ExampleApp',
          path: const [
            'C:',
            'Users',
            'Fixture',
            'AppData',
            'Local',
            'ExampleApp',
          ],
        ),
      );
      expect(insight.role, FolderRole.applicationData);
      expect(insight.probableOwner, 'ExampleApp');
      expect(insight.riskLevel, RiskLevel.review);
    },
  );

  test('unknown folder remains unknown', () {
    final insight = engine.explain(
      _observation(
        platform: PickLogicPlatform.synthetic,
        name: 'x7_state',
        path: const ['Fixture', 'x7_state'],
      ),
    );
    expect(insight.role, FolderRole.unknown);
    expect(insight.riskLevel, RiskLevel.unknown);
    expect(insight.confidence, lessThan(0.5));
  });

  test(
    'shared scanner emits every folder and keeps provider failures',
    () async {
      const roots = <FolderNode>[
        FolderNode(
          locator: 'synthetic://root',
          displayName: 'Root',
          pathSegments: ['Root'],
          platform: PickLogicPlatform.synthetic,
        ),
      ];
      final emitted = <FolderInsight>[];
      final result = await const FolderTreeScanner().scan(
        roots: roots,
        onInsight: emitted.add,
        inspector: (node, cancellation) async {
          if (node.locator.endsWith('blocked')) throw StateError('blocked');
          return FolderInspection(
            observation: _observation(
              platform: PickLogicPlatform.synthetic,
              name: node.displayName,
              path: node.pathSegments,
              locator: node.locator,
            ),
            children: node.locator == 'synthetic://root'
                ? const <FolderNode>[
                    FolderNode(
                      locator: 'synthetic://root/Documents',
                      displayName: 'Documents',
                      pathSegments: ['Root', 'Documents'],
                      platform: PickLogicPlatform.synthetic,
                    ),
                    FolderNode(
                      locator: 'synthetic://root/blocked',
                      displayName: 'blocked',
                      pathSegments: ['Root', 'blocked'],
                      platform: PickLogicPlatform.synthetic,
                    ),
                  ]
                : const <FolderNode>[],
          );
        },
      );
      expect(result.insights, hasLength(3));
      expect(emitted, hasLength(3));
      expect(result.failures, 1);
      expect(result.complete, isTrue);
    },
  );
}

FolderObservation _observation({
  required PickLogicPlatform platform,
  required String name,
  required List<String> path,
  String locator = 'synthetic://folder',
}) => FolderObservation(
  locator: locator,
  displayName: name,
  pathSegments: path,
  platform: platform,
  directFileCount: 0,
  directDirectoryCount: 0,
  directFileBytes: 0,
  mimeFamilyCounts: const <String, int>{},
);
