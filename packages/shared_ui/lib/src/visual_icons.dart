import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

enum PickLogicVisualIcon {
  image,
  audio,
  video,
  application,
  archive,
  document,
  folder,
  storage,
  pdf,
  screenshot,
}

class PickLogicIcon extends StatelessWidget {
  const PickLogicIcon(
    this.icon, {
    super.key,
    this.size = 44,
    this.semanticLabel,
  });

  final PickLogicVisualIcon icon;
  final double size;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      'assets/icons/${icon.name}.svg',
      package: 'picklogic_shared_ui',
      width: size,
      height: size,
      fit: BoxFit.contain,
      semanticsLabel: semanticLabel,
    );
  }
}
