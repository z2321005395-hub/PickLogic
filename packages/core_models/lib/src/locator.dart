import 'enums.dart';

final class FileLocator {
  const FileLocator({
    required this.value,
    required this.sourceKind,
    required this.platform,
  }) : assert(value != '');

  final String value;
  final SourceKind sourceKind;
  final PickLogicPlatform platform;

  String get redactedLabel => '${platform.name}:${sourceKind.name}';

  @override
  bool operator ==(Object other) =>
      other is FileLocator &&
      other.value == value &&
      other.sourceKind == sourceKind &&
      other.platform == platform;

  @override
  int get hashCode => Object.hash(value, sourceKind, platform);

  @override
  String toString() => 'FileLocator($redactedLabel)';
}
