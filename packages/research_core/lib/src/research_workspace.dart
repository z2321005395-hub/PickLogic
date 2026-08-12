enum ResearchBucket {
  literature,
  rawData,
  processedData,
  figures,
  scripts,
  notes,
  presentations,
  manuscripts,
}

final class ResearchLink {
  const ResearchLink({
    required this.projectId,
    required this.fileId,
    required this.bucket,
    this.note = '',
  });

  final String projectId;
  final String fileId;
  final ResearchBucket bucket;
  final String note;
}

final class ResearchBucketSummary {
  const ResearchBucketSummary({required this.bucket, required this.links});

  final ResearchBucket bucket;
  final List<ResearchLink> links;

  int get count => links.length;
}

final class ResearchWorkspace {
  ResearchWorkspace({required this.id, required this.name}) {
    if (id.trim().isEmpty) {
      throw ArgumentError.value(id, 'id', 'Must not be empty.');
    }
    if (name.trim().isEmpty) {
      throw ArgumentError.value(name, 'name', 'Must not be empty.');
    }
  }

  final String id;
  final String name;
  final List<ResearchLink> _links = [];

  List<ResearchLink> get links => List.unmodifiable(_links);

  List<ResearchBucketSummary> get bucketSummaries => [
    for (final bucket in ResearchBucket.values)
      ResearchBucketSummary(bucket: bucket, links: linksFor(bucket)),
  ];

  void link(ResearchLink link) {
    if (link.projectId != id) {
      throw ArgumentError.value(
        link.projectId,
        'projectId',
        'Project mismatch.',
      );
    }
    if (link.fileId.trim().isEmpty) {
      throw ArgumentError.value(link.fileId, 'fileId', 'Must not be empty.');
    }
    _links.removeWhere((item) => item.fileId == link.fileId);
    _links.add(link);
  }

  bool unlink(String fileId) {
    final previousLength = _links.length;
    _links.removeWhere((item) => item.fileId == fileId);
    return _links.length != previousLength;
  }

  List<ResearchLink> linksFor(ResearchBucket bucket) =>
      List.unmodifiable(_links.where((link) => link.bucket == bucket));
}
