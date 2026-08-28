import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:pdfrx/pdfrx.dart';

import 'src/app.dart';
import 'src/pdf_content_edit_smoke.dart';
import 'src/pro_pdf_reader.dart';

Future<void> main(List<String> arguments) async {
  WidgetsFlutterBinding.ensureInitialized();
  await pdfrxFlutterInitialize();
  if (arguments.contains('--synthetic-pdf-smoke')) {
    exit(await runSyntheticPdfEngineSmoke());
  }
  if (arguments.contains('--synthetic-pdf-content-edit-smoke')) {
    exit(await runSyntheticPdfContentEditSmoke());
  }
  runPickLogicDesktop(pro: true);
}
