from pathlib import Path

path = Path('lib/features/duel/online_duel_screen.dart')
text = path.read_text(encoding='utf-8')
text = text.replace('    final draw = snapshot.winnerSeat == null;\n', '', 1)
old = """    final deadline = widget.deadline;
    final remaining = deadline == null
        ? null
        : deadline.difference(DateTime.now()).inSeconds.clamp(0, 30);"""
new = """    final remaining = widget.deadline
        ?.difference(DateTime.now())
        .inSeconds
        .clamp(0, 30);"""
if old not in text:
    raise SystemExit('reconnect countdown lint pattern missing')
text = text.replace(old, new, 1)
path.write_text(text, encoding='utf-8')
print('online duel analyzer cleanup applied')
