# Sudoku Duel

A simple Flutter Sudoku game with a guided career, a daily puzzle, and a shared-board local duel prototype.

English is the canonical source language. Android is prepared for Google Play's **App strings translation using Gemini**, while iOS uses the same keys through an Xcode-compatible String Catalog.

## Current features

- Interactive 4×4 beginner tutorial
- 30 career levels across five difficulties
- Validated Sudoku puzzle and solution catalog
- Notes, erase, undo, and hints
- Timer, mistakes, stars, and personal best records
- Deterministic daily Sudoku
- Two-player local duel on one device
- 10-second duel turns, +10 for a correct move, and -5 for an incorrect move
- Light, dark, and high-contrast themes
- Local career and settings persistence
- English source interface with 22 declared app locales
- Android native string bridge for Google Play-generated translations
- iOS String Catalog support
- Sudoku engine and home-screen widget tests

## Run

```bash
flutter pub get
flutter run
```

## Validation

Validate the repository structure, imports, and puzzle consistency:

```bash
python3 tool/validate_prototype.py
```

Validate that Dart, Android, and iOS expose the same localization keys:

```bash
python3 tool/validate_localizations.py
```

Run the complete Flutter checks:

```bash
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
```

## Localization

See [`docs/LOCALIZATION.md`](docs/LOCALIZATION.md) for:

- the supported language list
- Google Play Console's Gemini app-string translation steps
- the iOS Xcode agent and String Catalog workflow
- rules for adding new user-visible text

## Next online phase

- Firebase Anonymous Authentication
- Cloudflare Worker
- Matchmaker and GameRoom Durable Objects
- WebSocket reconnection
- Friend rooms and quick matchmaking

See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for the planned online boundaries.
