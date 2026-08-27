import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:pdfrx/pdfrx.dart';

import 'src/app.dart';
import 'src/pro_pdf_reader.dart';

Future<void> main(List<String> arguments) async {
  WidgetsFlutterBinding.ensureInitialized();
  await pdfrxFlutterInitialize();
  if (arguments.contains('--synthetic-pdf-smoke')) {
    exit(await runSyntheticPdfEngineSmoke());
  }
  runPickLogicDesktop(pro: true);
}
