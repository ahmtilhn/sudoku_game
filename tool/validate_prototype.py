from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
REQUIRED = [
    'pubspec.yaml',
    'lib/main.dart',
    'lib/app.dart',
    'lib/domain/sudoku.dart',
    'lib/data/puzzle_catalog.dart',
    'lib/features/game/game_screen.dart',
    'lib/features/duel/duel_screen.dart',
    'test/sudoku_engine_test.dart',
]

errors = []
for relative in REQUIRED:
    if not (ROOT / relative).is_file():
        errors.append(f'Missing required file: {relative}')

for dart_file in list((ROOT / 'lib').rglob('*.dart')) + list((ROOT / 'test').rglob('*.dart')):
    source = dart_file.read_text(encoding='utf-8')
    for imported in re.findall(r"import '([^']+)';", source):
        if imported.startswith('package:sudoku_game/'):
            target = ROOT / 'lib' / imported.removeprefix('package:sudoku_game/')
        elif imported.startswith('.'):
            target = (dart_file.parent / imported).resolve()
        else:
            continue
        if not target.is_file():
            errors.append(f'{dart_file.relative_to(ROOT)} imports missing {imported}')

catalog = (ROOT / 'lib/data/puzzle_catalog.dart').read_text(encoding='utf-8')
required_catalog_patterns = {
    'dynamic puzzle generator': r'static SudokuPuzzle generatePuzzle\(',
    'seeded solved grid generation': r'_generateSolvedGrid\(random\)',
    'unique puzzle carving': r'_carveUniquePuzzle\(',
    'unique solution checker': r'static bool hasUniqueSolution\(',
    'daily puzzle factory': r'static SudokuPuzzle dailyPuzzle\(',
    'duel puzzle factory': r'static SudokuPuzzle duelPuzzle\(',
}

for name, pattern in required_catalog_patterns.items():
    if not re.search(pattern, catalog):
        errors.append(f'Missing catalog capability: {name}')

for difficulty in ('beginner', 'easy', 'medium', 'hard', 'expert'):
    if f'SudokuDifficulty.{difficulty}' not in catalog:
        errors.append(f'Missing target clue count for difficulty: {difficulty}')

engine_test = (ROOT / 'test/sudoku_engine_test.dart').read_text(encoding='utf-8')
required_test_patterns = {
    'generated puzzle validity test': 'generated puzzles have a valid shape and one solution',
    'deterministic seed test': 'the same seed produces the same puzzle',
    'duel difficulty test': 'duel puzzle keeps the selected difficulty',
}

for name, marker in required_test_patterns.items():
    if marker not in engine_test:
        errors.append(f'Missing engine test coverage: {name}')

if errors:
    print('\n'.join(f'ERROR: {error}' for error in errors))
    sys.exit(1)

print(f'Prototype validation passed: {len(REQUIRED)} required files and dynamic puzzle generation coverage.')
