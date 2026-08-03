import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sudoku_game/widgets/responsive_layout.dart';

void main() {
  const sizes = <Size>[
    Size(320, 568),
    Size(360, 640),
    Size(390, 844),
    Size(412, 915),
    Size(600, 960),
    Size(768, 1024),
    Size(820, 1180),
  ];

  for (final size in sizes) {
    for (final scale in <double>[1, 1.3, 2]) {
      testWidgets('portrait ${size.width}x${size.height} at ${scale}x',
          (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale),
            ),
            child: child!,
          ),
          home: Scaffold(
            body: SafeArea(
              child: AdaptiveActionGroup(children: [
                OutlinedButton(
                  onPressed: () {},
                  child: const Text('Decline request'),
                ),
                FilledButton(
                  onPressed: () {},
                  child: const Text('Accept challenge'),
                ),
              ]),
            ),
          ),
        ));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('bottom sheet scrolls at 320x568 with 2x text', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 568);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: const TextScaler.linear(2),
        ),
        child: child!,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: FilledButton(
            onPressed: () => showAdaptiveBottomSheet<void>(
              context: context,
              builder: (_) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < 12; i++)
                    ListTile(title: Text('Responsive action $i')),
                ],
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.byType(SingleChildScrollView), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
