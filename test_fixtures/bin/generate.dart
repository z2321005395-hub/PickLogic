import 'dart:convert';
import 'dart:io';

import 'package:picklogic_test_fixtures/picklogic_test_fixtures.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 2 || arguments.first != '--output') {
    stderr.writeln(
      'Usage: dart run test_fixtures/bin/generate.dart --output <dir>',
    );
    exitCode = 64;
    return;
  }
  final root = Directory(arguments[1]);
  final files = await const SyntheticFixtureSet().writeTo(root);
  stdout.writeln(jsonEncode({'generatedFiles': files.length}));
}
