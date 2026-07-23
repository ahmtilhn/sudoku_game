import 'package:flutter/material.dart';

import 'app.dart';
import 'data/local_progress_store.dart';
import 'localization/app_strings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = await LocalProgressStore.create();
  final strings = await AppStrings.load();
  runApp(SudokuApp(store: store, strings: strings));
}
