import 'package:flutter/material.dart';
import 'package:picklogic_core_models/picklogic_core_models.dart';

final class SafeModeBanner extends StatelessWidget {
  const SafeModeBanner({super.key, this.mode = const DeveloperSafeMode.on()});

  final DeveloperSafeMode mode;

  @override
  Widget build(BuildContext context) {
    final chinese = Localizations.localeOf(context).languageCode == 'zh';
    final label = mode.enabled
        ? (chinese
              ? '开发者安全模式：已开启，真实文件只读'
              : 'Developer Safe Mode: On, real files are read-only')
        : (chinese ? '开发者安全模式：已关闭' : 'Developer Safe Mode: Off');
    return Material(
      color: mode.enabled
          ? Theme.of(context).colorScheme.tertiaryContainer
          : Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              mode.enabled ? Icons.shield_outlined : Icons.warning_amber,
              size: 16,
            ),
            const SizedBox(width: 8),
            Text(label, style: Theme.of(context).textTheme.labelMedium),
          ],
        ),
      ),
    );
  }
}
