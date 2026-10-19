import 'dart:math' as math;

import '../domain/models.dart';
import 'text_match.dart';

class _IndexedDoc {
  _IndexedDoc(this.unit, this.tokens) : termFrequency = _counts(tokens);

  final EvidenceUnit unit;
  final List<String> tokens;
  final Map<String, int> termFrequency;

  static Map<String, int> _counts(List<String> tokens) {
    final counts = <String, int>{};
    for (final token in tokens) {
      counts[token] = (counts[token] ?? 0) + 1;
    }
    return counts;
  }
}

/// BM25 index over one case corpus.
///
/// Filters (modality, source kind, site) are applied before scoring. An empty
/// query returns the newest units in the filter, with a zero score, so the
/// desk can browse without pretending a text match happened.
class EvidenceIndex {
  EvidenceIndex(List<EvidenceUnit> units)
    : _docs = units
          .map((unit) => _IndexedDoc(unit, indexTokens(unit.searchableText)))
          .toList() {
    final documentCount = _docs.length;
    if (documentCount == 0) {
      _averageLength = 1;
      return;
    }
    var total = 0;
    for (final doc in _docs) {
      total += doc.tokens.length;
      for (final term in doc.termFrequency.keys) {
        _documentFrequency[term] = (_documentFrequency[term] ?? 0) + 1;
      }
    }
    _averageLength = math.max(1, total / documentCount);
  }

  static const _k1 = 1.2;
  static const _b = 0.25;

  final List<_IndexedDoc> _docs;
  final Map<String, int> _documentFrequency = {};
  late final double _averageLength;

  List<RetrievalHit> search(RetrievalQuery query) {
    final filtered = _docs.where((doc) {
      final unit = doc.unit;
      if (query.modality != null && unit.modality != query.modality) {
        return false;
      }
      if (query.sourceKind != null && unit.sourceKind != query.sourceKind) {
        return false;
      }
      if (query.site != null && unit.site != query.site) {
        return false;
      }
      return true;
    }).toList();

    final limit = math.max(0, query.limit);
    if (limit == 0 || filtered.isEmpty) {
      return const [];
    }

    final terms = indexTokens(query.text).toSet().toList();
    if (terms.isEmpty) {
      final browsed = [...filtered]
        ..sort((a, b) => b.unit.observedAt.compareTo(a.unit.observedAt));
      return browsed
          .take(limit)
          .map(
            (doc) =>
                RetrievalHit(unit: doc.unit, score: 0, matchedTerms: const []),
          )
          .toList();
    }

    final hits = <RetrievalHit>[];
    for (final doc in filtered) {
      final matched = <String>[];
      var score = 0.0;
      final length = math.max(1, doc.tokens.length);
      for (final term in terms) {
        final frequency = doc.termFrequency[term] ?? 0;
        if (frequency == 0) {
          continue;
        }
        matched.add(term);
        final df = _documentFrequency[term] ?? 0;
        final idf = math.log(1 + (_docs.length - df + 0.5) / (df + 0.5));
        final denominator =
            frequency + _k1 * (1 - _b + _b * length / _averageLength);
        score += idf * (frequency * (_k1 + 1)) / denominator;
        if (indexTokens(doc.unit.title).contains(term)) {
          score += 0.35 * idf;
        }
      }
      if (matched.isEmpty) {
        continue;
      }
      hits.add(
        RetrievalHit(unit: doc.unit, score: score, matchedTerms: matched),
      );
    }

    hits.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) {
        return byScore;
      }
      return a.unit.id.compareTo(b.unit.id);
    });
    return hits.take(limit).toList();
  }
}
