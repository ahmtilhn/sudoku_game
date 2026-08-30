import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sudoku_game/core/user_safe_error.dart';
import 'package:sudoku_game/localization/app_strings.dart';
import 'package:sudoku_game/services/economy_api_client.dart';
import 'package:sudoku_game/services/social_api_client.dart';

void main() {
  testWidgets('expected API errors are converted without FlutterError noise', (
    tester,
  ) async {
    final reported = <FlutterErrorDetails>[];
    final previousHandler = FlutterError.onError;
    FlutterError.onError = reported.add;
    addTearDown(() => FlutterError.onError = previousHandler);

    await tester.pumpWidget(
      AppStringsScope(
        strings: AppStrings.forTesting(),
        child: const MaterialApp(home: Scaffold(body: SizedBox())),
      ),
    );

    final context = tester.element(find.byType(SizedBox));

    UserSafeError.message(
      context,
      const SocialApiException(
        503,
        'The competitive economy is temporarily unavailable.',
      ),
    );
    UserSafeError.message(
      context,
      const EconomyApiException(403, 'App Check could not verify.'),
    );

    expect(reported, isEmpty);
  });

  testWidgets('unexpected errors are still reported', (tester) async {
    final reported = <FlutterErrorDetails>[];
    final previousHandler = FlutterError.onError;
    FlutterError.onError = reported.add;
    addTearDown(() => FlutterError.onError = previousHandler);

    await tester.pumpWidget(
      AppStringsScope(
        strings: AppStrings.forTesting(),
        child: const MaterialApp(home: Scaffold(body: SizedBox())),
      ),
    );

    final context = tester.element(find.byType(SizedBox));
    UserSafeError.message(context, StateError('boom'));

    expect(reported.single.exception, isA<StateError>());
  });
}
