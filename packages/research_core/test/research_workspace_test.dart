import 'package:picklogic_research_core/picklogic_research_core.dart';
import 'package:test/test.dart';

void main() {
  test('virtual links replace a file association without moving a file', () {
    final workspace = ResearchWorkspace(id: 'p1', name: 'Synthetic project');
    workspace.link(
      const ResearchLink(
        projectId: 'p1',
        fileId: 'f1',
        bucket: ResearchBucket.rawData,
      ),
    );
    workspace.link(
      const ResearchLink(
        projectId: 'p1',
        fileId: 'f1',
        bucket: ResearchBucket.processedData,
      ),
    );
    expect(workspace.links, hasLength(1));
    expect(workspace.links.single.bucket, ResearchBucket.processedData);
  });

  test('bucket summaries include empty and populated virtual buckets', () {
    final workspace = ResearchWorkspace(id: 'p1', name: 'Synthetic project')
      ..link(
        const ResearchLink(
          projectId: 'p1',
          fileId: 'paper-1',
          bucket: ResearchBucket.literature,
        ),
      )
      ..link(
        const ResearchLink(
          projectId: 'p1',
          fileId: 'figure-1',
          bucket: ResearchBucket.figures,
        ),
      );

    expect(workspace.bucketSummaries, hasLength(ResearchBucket.values.length));
    expect(
      workspace.bucketSummaries
          .singleWhere((summary) => summary.bucket == ResearchBucket.figures)
          .count,
      1,
    );
    expect(workspace.linksFor(ResearchBucket.scripts), isEmpty);
    expect(workspace.unlink('figure-1'), isTrue);
    expect(workspace.linksFor(ResearchBucket.figures), isEmpty);
  });

  test('workspace rejects cross-project virtual links', () {
    final workspace = ResearchWorkspace(id: 'p1', name: 'Synthetic project');
    expect(
      () => workspace.link(
        const ResearchLink(
          projectId: 'p2',
          fileId: 'paper-1',
          bucket: ResearchBucket.literature,
        ),
      ),
      throwsArgumentError,
    );
  });
}
