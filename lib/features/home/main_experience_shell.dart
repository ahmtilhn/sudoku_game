import 'package:flutter/material.dart';

import '../../data/local_progress_store.dart';
import 'professional_home_screen.dart';

class MainExperienceShell extends StatelessWidget {
  const MainExperienceShell({super.key, required this.store});

  final LocalProgressStore store;

  @override
  Widget build(BuildContext context) {
    return Scaffold(body: ProfessionalHomeScreen(store: store));
  }
}
