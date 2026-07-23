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
grids = re.findall(r"'([0-9]{81})'", catalog)
if len(grids) < 10:
    errors.append(f'Expected at least 10 puzzle/solution grids, found {len(grids)}')

def valid_solution(value: str) -> bool:
    board = [int(item) for item in value]
    required = set(range(1, 10))
    rows = [board[row * 9:(row + 1) * 9] for row in range(9)]
    columns = [board[column::9] for column in range(9)]
    boxes = []
    for box_row in range(3):
        for box_column in range(3):
            box = []
            for row in range(box_row * 3, box_row * 3 + 3):
                start = row * 9 + box_column * 3
                box.extend(board[start:start + 3])
            boxes.append(box)
    return all(set(group) == required for group in rows + columns + boxes)

for index in range(0, len(grids) - 1, 2):
    puzzle, solution = grids[index], grids[index + 1]
    if not valid_solution(solution):
        errors.append(f'Invalid solution grid at pair {index // 2 + 1}')
    if any(clue != '0' and clue != answer for clue, answer in zip(puzzle, solution)):
        errors.append(f'Puzzle clues do not match solution at pair {index // 2 + 1}')

if errors:
    print('\n'.join(f'ERROR: {error}' for error in errors))
    sys.exit(1)

print(f'Prototype validation passed: {len(REQUIRED)} required files, {len(grids) // 2} base puzzles.')
