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
}
