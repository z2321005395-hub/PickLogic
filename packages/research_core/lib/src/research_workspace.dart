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

final class ResearchWorkspace {
  ResearchWorkspace({required this.id, required this.name});

  final String id;
  final String name;
  final List<ResearchLink> _links = [];

  List<ResearchLink> get links => List.unmodifiable(_links);

  void link(ResearchLink link) {
    if (link.projectId != id) throw ArgumentError('Project mismatch');
    _links.removeWhere((item) => item.fileId == link.fileId);
    _links.add(link);
  }
}
