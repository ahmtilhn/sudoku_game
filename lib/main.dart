import 'package:flutter/material.dart';

import 'app.dart';
import 'data/local_progress_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = await LocalProgressStore.create();
  runApp(SudokuApp(store: store));
}
