/// Token and phrase matching shared by the index and the investigation policy.
///
/// Phrase checks keep negation words. Index tokens drop function words so BM25
/// is not dominated by "the" and "of".
library;

final _word = RegExp(r'[a-z0-9]+');

const negationWords = {'no', 'not', 'without', 'never', 'none'};

const indexStopwords = {
  'a',
  'an',
  'the',
  'of',
  'and',
  'to',
  'for',
  'in',
  'on',
  'with',
  'from',
  'by',
  'is',
  'are',
  'was',
  'were',
  'this',
  'that',
  'as',
  'at',
  'or',
  'be',
  'it',
  'its',
  'into',
  'over',
  'than',
  'then',
  'during',
  'while',
  'across',
  'under',
  'after',
  'before',
  'between',
};

List<String> phraseTokens(String input) {
  final lower = input.toLowerCase().replaceAll("'", '');
  return _word.allMatches(lower).map((match) => match.group(0)!).toList();
}

List<String> indexTokens(String input) {
  return phraseTokens(input)
      .where((token) => token.length > 1 && !indexStopwords.contains(token))
      .toList();
}

/// A period, semicolon, question or exclamation mark followed by space or the
/// end, or a newline. "42.5 ppm" stays one sentence.
final _sentenceBreak = RegExp(r'[.;!?](?=\s|$)|\n');

/// How many content tokens in front of a phrase a negation can reach.
const negationWindow = 3;

/// True when [phrase] occurs as consecutive tokens and no negation word sits
/// among the three content tokens in front of it, inside the same sentence.
///
/// Function words do not use up the window, so "no sign of a door ajar" is
/// negated. A sentence break ends it, so "No alarm. Door ajar." is not.
bool phraseMatches(String text, String phrase) {
  final need = phraseTokens(phrase);
  if (need.isEmpty) {
    return false;
  }
  for (final sentence in text.split(_sentenceBreak)) {
    if (_matchesIn(phraseTokens(sentence), need)) {
      return true;
    }
  }
  return false;
}

bool _matchesIn(List<String> tokens, List<String> need) {
  if (need.length > tokens.length) {
    return false;
  }
  for (var i = 0; i + need.length <= tokens.length; i++) {
    var aligned = true;
    for (var j = 0; j < need.length; j++) {
      if (tokens[i + j] != need[j]) {
        aligned = false;
        break;
      }
    }
    if (!aligned) {
      continue;
    }
    if (_negatedBefore(tokens, i)) {
      continue;
    }
    return true;
  }
  return false;
}

bool _negatedBefore(List<String> tokens, int start) {
  var content = 0;
  for (var k = start - 1; k >= 0 && content < negationWindow; k--) {
    final token = tokens[k];
    if (negationWords.contains(token)) {
      return true;
    }
    if (!indexStopwords.contains(token)) {
      content += 1;
    }
  }
  return false;
}
