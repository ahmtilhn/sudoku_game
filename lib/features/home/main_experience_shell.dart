import 'package:flutter/material.dart';

import '../../data/local_progress_store.dart';
import 'ux_root_screen.dart';

class MainExperienceShell extends StatelessWidget {
  const MainExperienceShell({super.key, required this.store});

  final LocalProgressStore store;

  @override
  Widget build(BuildContext context) {
    return Scaffold(body: UxRootScreen(store: store));
  }
}
