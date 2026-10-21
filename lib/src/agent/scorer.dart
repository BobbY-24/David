import '../domain/format.dart';
import '../domain/models.dart';
import '../retrieval/text_match.dart';

/// Scores one risk question against the evidence a run retrieved.
///
/// The agent owns retrieval, routing, the panel lenses, the memo, and the
/// rails. A scorer only answers "how much does this evidence support or
/// contradict this risk". `skip` holds evidence ids the caller excluded
/// (quarantined units, or the strongest unit in a leave-one-out lens), and
/// `contradictScale` lets a lens weigh falsifiers more heavily.
abstract interface class RiskScorer {
  RiskJudgment judge(
    RiskQuestion risk,
    List<RetrievalHit> retrieved,
    Set<String> skip,
    double contradictScale,
  );
}

/// Hand-written phrase signatures over BM25 hits. Offline and deterministic.
class PhraseScorer implements RiskScorer {
  const PhraseScorer();

  @override
  RiskJudgment judge(
    RiskQuestion risk,
    List<RetrievalHit> retrieved,
    Set<String> skip,
    double contradictScale,
  ) {
    final supporting = <RetrievalHit>[];
    final contradicting = <RetrievalHit>[];
    final matchedSupport = <String>[];
    final matchedContradict = <String>[];
    final missingSupport = <String>[];
    final usable = retrieved
        .where((hit) => !skip.contains(hit.unit.id))
        .toList();
    final supportScore = _scoreSignatures(
      signatures: risk.support,
      retrieved: usable,
      into: supporting,
      matched: matchedSupport,
      missing: missingSupport,
    );
    final contradictScore =
        _scoreSignatures(
          signatures: risk.contradict,
          retrieved: usable,
          into: contradicting,
          matched: matchedContradict,
          missing: null,
        ) *
        contradictScale;
    return RiskJudgment(
      riskId: risk.id,
      title: risk.title,
      statement: risk.statement,
      actionIfLead: risk.actionIfLead,
      supportScore: supportScore,
      contradictScore: contradictScore,
      net: supportScore - contradictScore,
      supporting: supporting,
      contradicting: contradicting,
      matchedSupport: matchedSupport,
      matchedContradict: matchedContradict,
      missingSupport: missingSupport,
    );
  }

  double _scoreSignatures({
    required List<Signature> signatures,
    required List<RetrievalHit> retrieved,
    required List<RetrievalHit> into,
    required List<String> matched,
    required List<String>? missing,
  }) {
    var total = 0.0;
    final seen = into.map((hit) => hit.unit.id).toSet();
    for (final signature in signatures) {
      RetrievalHit? best;
      for (final hit in retrieved) {
        if (!phraseMatches(hit.unit.searchableText, signature.phrase)) {
          continue;
        }
        if (best == null || hit.score > best.score) {
          best = hit;
        }
      }
      if (best == null) {
        missing?.add(signature.phrase);
        continue;
      }
      matched.add(signature.phrase);
      final norm = best.score / (best.score + 2.5);
      total += signature.weight * (0.65 + 0.35 * norm);
      if (seen.add(best.unit.id)) {
        into.add(best);
      }
    }
    return total;
  }
}

/// One unit of evidence a model cited for or against a risk.
class ModelEvidenceWeight {
  const ModelEvidenceWeight({
    required this.evidenceId,
    required this.weight,
    required this.note,
  });

  final String evidenceId;
  final double weight;
  final String note;
}

/// A model's weights for one risk question.
class ModelRiskScore {
  const ModelRiskScore({
    required this.riskId,
    this.support = const [],
    this.contradict = const [],
  });

  final String riskId;
  final List<ModelEvidenceWeight> support;
  final List<ModelEvidenceWeight> contradict;
}

/// Turns a model's per-risk evidence weights into [RiskJudgment]s.
///
/// The model never decides the outcome. Its weights are validated here: an id
/// that this run did not retrieve, or that the caller skipped, counts for
/// nothing, so a memo can only cite retrieved evidence. Later entries in a
/// list count for less (each is worth 80% of the one before it) and a total is
/// capped, so listing many weak units cannot out-vote one decisive unit.
class ModelScorer implements RiskScorer {
  ModelScorer(Iterable<ModelRiskScore> scores)
    : _byRisk = {for (final score in scores) score.riskId: score};

  static const minWeight = 0.1;
  static const maxWeight = 3.0;
  static const _decay = 0.8;
  static const _ceiling = 8.0;
  static const _noteChars = 100;

  final Map<String, ModelRiskScore> _byRisk;

  @override
  RiskJudgment judge(
    RiskQuestion risk,
    List<RetrievalHit> retrieved,
    Set<String> skip,
    double contradictScale,
  ) {
    final usable = {
      for (final hit in retrieved)
        if (!skip.contains(hit.unit.id)) hit.unit.id: hit,
    };
    final score = _byRisk[risk.id];
    final support = _tally(score?.support ?? const [], usable);
    final contradict = _tally(score?.contradict ?? const [], usable);
    final contradictScore = contradict.total * contradictScale;
    return RiskJudgment(
      riskId: risk.id,
      title: risk.title,
      statement: risk.statement,
      actionIfLead: risk.actionIfLead,
      supportScore: support.total,
      contradictScore: contradictScore,
      net: support.total - contradictScore,
      supporting: support.hits,
      contradicting: contradict.hits,
      matchedSupport: support.notes,
      matchedContradict: contradict.notes,
      missingSupport: const [],
    );
  }

  _Tally _tally(
    List<ModelEvidenceWeight> entries,
    Map<String, RetrievalHit> usable,
  ) {
    final best = <String, ModelEvidenceWeight>{};
    for (final entry in entries) {
      if (!usable.containsKey(entry.evidenceId) || entry.weight.isNaN) {
        continue;
      }
      final weight = entry.weight.clamp(minWeight, maxWeight).toDouble();
      final prior = best[entry.evidenceId];
      if (prior == null || weight > prior.weight) {
        best[entry.evidenceId] = ModelEvidenceWeight(
          evidenceId: entry.evidenceId,
          weight: weight,
          note: entry.note,
        );
      }
    }
    final ranked = best.values.toList()
      ..sort((a, b) {
        final byWeight = b.weight.compareTo(a.weight);
        return byWeight != 0 ? byWeight : a.evidenceId.compareTo(b.evidenceId);
      });
    var total = 0.0;
    var factor = 1.0;
    final hits = <RetrievalHit>[];
    final notes = <String>[];
    for (final entry in ranked) {
      total += entry.weight * factor;
      factor *= _decay;
      final hit = usable[entry.evidenceId]!;
      hits.add(hit);
      notes.add(
        entry.note.trim().isEmpty
            ? hit.unit.title
            : excerpt(entry.note, _noteChars),
      );
    }
    return _Tally(total > _ceiling ? _ceiling : total, hits, notes);
  }
}

class _Tally {
  const _Tally(this.total, this.hits, this.notes);

  final double total;
  final List<RetrievalHit> hits;
  final List<String> notes;
}
