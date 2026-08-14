enum ProModuleId {
  literatureLibrary,
  pdfReader,
  translation,
  citation,
  researchWorkspace,
  systemInsight,
}

final class ProModuleDescriptor {
  const ProModuleDescriptor({
    required this.id,
    required this.enabledByDefault,
    required this.optionalHeavyComponent,
  });

  final ProModuleId id;
  final bool enabledByDefault;
  final bool optionalHeavyComponent;
}

const proModuleRegistry = <ProModuleDescriptor>[
  ProModuleDescriptor(
    id: ProModuleId.literatureLibrary,
    enabledByDefault: true,
    optionalHeavyComponent: false,
  ),
  ProModuleDescriptor(
    id: ProModuleId.pdfReader,
    enabledByDefault: true,
    optionalHeavyComponent: false,
  ),
  ProModuleDescriptor(
    id: ProModuleId.translation,
    enabledByDefault: false,
    optionalHeavyComponent: false,
  ),
  ProModuleDescriptor(
    id: ProModuleId.citation,
    enabledByDefault: true,
    optionalHeavyComponent: false,
  ),
  ProModuleDescriptor(
    id: ProModuleId.researchWorkspace,
    enabledByDefault: true,
    optionalHeavyComponent: false,
  ),
  ProModuleDescriptor(
    id: ProModuleId.systemInsight,
    enabledByDefault: true,
    optionalHeavyComponent: false,
  ),
];
