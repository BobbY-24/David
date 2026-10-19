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

/// True when [phrase] occurs as consecutive tokens and the three tokens in
/// front of that occurrence do not negate it.
bool phraseMatches(String text, String phrase) {
  final tokens = phraseTokens(text);
  final need = phraseTokens(phrase);
  if (need.isEmpty || need.length > tokens.length) {
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
    final windowStart = i >= 3 ? i - 3 : 0;
    final prefix = tokens.sublist(windowStart, i);
    if (prefix.any(negationWords.contains)) {
      continue;
    }
    return true;
  }
  return false;
}
