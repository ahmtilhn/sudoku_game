String sudokuSymbol(int value) {
  if (value <= 0) return '';
  if (value <= 9) return '$value';
  final letterIndex = value - 10;
  if (letterIndex >= 0 && letterIndex < 26) {
    return String.fromCharCode('A'.codeUnitAt(0) + letterIndex);
  }
  return '$value';
}

String sudokuSpokenValue(int value) {
  if (value <= 9) return '$value';
  return sudokuSymbol(value);
}
