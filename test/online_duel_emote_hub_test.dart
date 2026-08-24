import 'package:flutter_test/flutter_test.dart';
import 'package:sudoku_game/services/online_duel_emote_hub.dart';

void main() {
  test('sends a whitelisted emote and immediately applies cooldown', () {
    final sent = <String>[];
    final hub = OnlineDuelEmoteHub();
    final owner = hub.attach(
      sender: (emoteId) {
        sent.add(emoteId);
        return true;
      },
    );
    hub.setMatchActive(owner, true);

    expect(hub.send('laugh'), isTrue);
    expect(sent, <String>['laugh']);
    expect(hub.outgoingEmoteId, 'laugh');
    expect(hub.onCooldown, isTrue);
    expect(hub.send('fire'), isFalse);
    expect(hub.send('not-allowed'), isFalse);

    hub.detach(owner);
  });

  test('local mute suppresses incoming opponent emotes', () {
    final hub = OnlineDuelEmoteHub();
    final owner = hub.attach(sender: (_) => true);
    hub.setMatchActive(owner, true);

    hub.toggleMute();
    hub.receive(owner, 'smile');

    expect(hub.muted, isTrue);
    expect(hub.incomingEmoteId, isNull);

    hub.toggleMute();
    hub.receive(owner, 'respect');
    expect(hub.incomingEmoteId, 'respect');

    hub.detach(owner);
  });

  test('emotes cannot be sent while the match is inactive', () {
    final sent = <String>[];
    final hub = OnlineDuelEmoteHub();
    final owner = hub.attach(
      sender: (emoteId) {
        sent.add(emoteId);
        return true;
      },
    );

    expect(hub.send('smile'), isFalse);
    expect(sent, isEmpty);

    hub.detach(owner);
  });
}
