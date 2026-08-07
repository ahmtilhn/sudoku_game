from pathlib import Path

path = Path('test/online_duel_lifecycle_hotfix_test.dart')
text = path.read_text(encoding='utf-8')
old = "    expect(source, contains('identity'));\n"
new = "    expect(source, contains('nameAndPresence'));\n"
if old not in text:
    raise SystemExit('lifecycle contract marker not found')
path.write_text(text.replace(old, new, 1), encoding='utf-8')
