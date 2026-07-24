from __future__ import annotations

from pathlib import Path

PROJECT_FILE = Path("ios/Runner.xcodeproj/project.pbxproj")
APP_BUNDLE_ID = "com.devoviastudio.sudoku"
TEST_BUNDLE_ID = f"{APP_BUNDLE_ID}.RunnerTests"
DEPLOYMENT_TARGET = "15.0"


def main() -> None:
    if not PROJECT_FILE.exists():
        raise SystemExit(f"Missing Xcode project: {PROJECT_FILE}")

    original = PROJECT_FILE.read_text(encoding="utf-8")
    updated = original

    updated = updated.replace(
        "PRODUCT_BUNDLE_IDENTIFIER = com.example.sudokuGame.RunnerTests;",
        f"PRODUCT_BUNDLE_IDENTIFIER = {TEST_BUNDLE_ID};",
    )
    updated = updated.replace(
        "PRODUCT_BUNDLE_IDENTIFIER = com.example.sudokuGame;",
        f"PRODUCT_BUNDLE_IDENTIFIER = {APP_BUNDLE_ID};",
    )
    updated = updated.replace(
        "IPHONEOS_DEPLOYMENT_TARGET = 13.0;",
        f"IPHONEOS_DEPLOYMENT_TARGET = {DEPLOYMENT_TARGET};",
    )

    invalid_values = (
        "com.example.sudokuGame",
        "IPHONEOS_DEPLOYMENT_TARGET = 13.0;",
    )
    remaining = [value for value in invalid_values if value in updated]
    if remaining:
        raise SystemExit(
            "Xcode project still contains unexpected placeholder values: "
            + ", ".join(remaining)
        )

    app_count = updated.count(
        f"PRODUCT_BUNDLE_IDENTIFIER = {APP_BUNDLE_ID};"
    )
    test_count = updated.count(
        f"PRODUCT_BUNDLE_IDENTIFIER = {TEST_BUNDLE_ID};"
    )
    deployment_count = updated.count(
        f"IPHONEOS_DEPLOYMENT_TARGET = {DEPLOYMENT_TARGET};"
    )

    if app_count != 3 or test_count != 3 or deployment_count < 3:
        raise SystemExit(
            "Unexpected Xcode project structure: "
            f"app IDs={app_count}, test IDs={test_count}, "
            f"deployment targets={deployment_count}."
        )

    if updated != original:
        PROJECT_FILE.write_text(updated, encoding="utf-8")
        print(f"Updated {PROJECT_FILE}")
    else:
        print(f"{PROJECT_FILE} is already configured")

    print(f"App bundle ID: {APP_BUNDLE_ID}")
    print(f"Test bundle ID: {TEST_BUNDLE_ID}")
    print(f"Minimum iOS: {DEPLOYMENT_TARGET}")


if __name__ == "__main__":
    main()
