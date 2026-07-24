import 'package:flutter_test/flutter_test.dart';
import 'package:sudoku_game/services/reminder_message_catalog.dart';

void main() {
  test('reminder catalog provides more than one thousand unique messages', () {
    final messages = ReminderMessageCatalog.allMessages();

    expect(ReminderMessageCatalog.uniqueMessageCount, 1152);
    expect(messages.length, 1152);
    expect(messages.toSet().length, 1152);
  });

  test('the same seed gives a stable shuffled reminder order', () {
    final first = ReminderMessageCatalog.shuffled(seed: 42);
    final second = ReminderMessageCatalog.shuffled(seed: 42);

    expect(first.take(63), orderedEquals(second.take(63)));
    expect(first.take(63).toSet().length, 63);
  });
}
