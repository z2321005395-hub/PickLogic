import 'dart:io';

import 'src/app.dart';
import 'src/pro_pdf_reader.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.contains('--synthetic-pdf-smoke')) {
    exit(await runSyntheticPdfEngineSmoke());
  }
  runPickLogicDesktop(pro: true);
}
