import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sudoku_game/core/app_theme.dart';
import 'package:sudoku_game/localization/app_strings.dart';
import 'package:sudoku_game/services/online_duel_emote_hub.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('compact inline emote stays inside ready control height', (
    tester,
  ) async {
    final hub = OnlineDuelEmoteHub.instance;
    final owner = hub.attach(sender: (_) => true);
    addTearDown(() => hub.detach(owner));
    hub.setMatchActive(owner, true);

    await tester.pumpWidget(
      AppStringsScope(
        strings: AppStrings.forTesting(),
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const Scaffold(
            body: Center(
              child: SizedBox(
                width: 56,
                height: 56,
                child: Center(
                  child: OnlineDuelInlineEmoteSurface(
                    compact: true,
                    accent: Color(0xFFFFC94D),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byIcon(Icons.add_reaction_outlined), findsOneWidget);

    hub.receive(owner, 'respect');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byType(OnlineDuelEmoteVisual), findsOneWidget);
    expect(tester.takeException(), isNull);

    final inlineSurface = find.byKey(
      const ValueKey<String>('online-duel-inline-emotes'),
    );
    expect(inlineSurface, findsOneWidget);
    expect(tester.getSize(inlineSurface), const Size(48, 48));

    await tester.pump(const Duration(seconds: 3));
  });
}
