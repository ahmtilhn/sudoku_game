from __future__ import annotations

import re
from pathlib import Path

root = Path(__file__).resolve().parents[1]
original = root / 'tool/apply_challenge_client_hardening.py'
source = original.read_text(encoding='utf-8')

pattern = re.compile(
    r"source = replace_once\(\n"
    r"    source,\n"
    r"    \"      await _economy\.refresh\(showLoading: false\);.*?"
    r"    \"invitation shared room open\",\n"
    r"\)\n",
    re.S,
)
source, count = pattern.subn('', source, count=1)
if count != 1:
    raise RuntimeError(f'expected to remove one redundant invitation room patch, found {count}')

namespace = {
    '__file__': str(original),
    '__name__': '__main__',
}
exec(compile(source, str(original), 'exec'), namespace)

invitation_path = root / 'lib/features/social/ux_challenge_invitation_screen.dart'
invitation = invitation_path.read_text(encoding='utf-8')
old = """        final active = await _social.activeMatch();
        final roomId = active?['roomId']?.toString().trim();
        if (roomId != null && roomId.isNotEmpty) {
          await _openRoom(roomId);
          return true;
        }
"""
new = """        final active = await _social.activeMatch();
        final activeChallengeId = active?['challengeId']?.toString();
        final roomId = active?['roomId']?.toString().trim();
        if (activeChallengeId == widget.challengeId &&
            roomId != null &&
            roomId.isNotEmpty) {
          await _openRoom(roomId);
          return true;
        }
"""
if invitation.count(old) != 1:
    raise RuntimeError('accepted challenge recovery block was not found exactly once')
invitation_path.write_text(invitation.replace(old, new, 1), encoding='utf-8')
print('Challenge client hardening v2 applied.')
