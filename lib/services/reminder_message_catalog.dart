import 'dart:math';

class ReminderMessageCatalog {
  const ReminderMessageCatalog._();

  static const List<String> _openers = <String>[
    'Your next Sudoku is waiting.',
    'A fresh grid just challenged you.',
    'Your brain deserves a quick workout.',
    'The board is ready when you are.',
    'A new puzzle wants your attention.',
    'Today’s logic challenge has arrived.',
    'Your next winning streak starts here.',
    'One clever move can change the board.',
    'The Sudoku arena is calling.',
    'A quiet challenge is ready for you.',
    'Your daily focus break is here.',
    'Another puzzle is ready to be conquered.',
  ];

  static const List<String> _challenges = <String>[
    'Can you finish without a single mistake?',
    'Can you beat your latest performance?',
    'Try a harder difficulty this time.',
    'See how far pure logic can take you.',
    'Protect your three-mistake limit.',
    'Build a cleaner winning streak today.',
    'Find the first hidden number now.',
    'Challenge yourself before someone else does.',
    'Prove that this grid cannot stop you.',
    'Turn a few focused minutes into a win.',
    'Solve one row and let momentum take over.',
    'Show the board who is in control.',
  ];

  static const List<String> _closers = <String>[
    'Open Sudoku Duel and take the first move.',
    'Your next victory may be one tap away.',
    'Start now and keep your streak alive.',
    'The challenge only begins when you open it.',
    'A focused minute is all you need to begin.',
    'Step into the grid and prove it.',
    'Play now before the puzzle wins by default.',
    'Tap in and claim today’s challenge.',
  ];

  static int get uniqueMessageCount =>
      _openers.length * _challenges.length * _closers.length;

  static List<String> allMessages() {
    return <String>[
      for (final opener in _openers)
        for (final challenge in _challenges)
          for (final closer in _closers) '$opener $challenge $closer',
    ];
  }

  static List<String> shuffled({required int seed}) {
    final messages = allMessages();
    messages.shuffle(Random(seed));
    return messages;
  }
}
