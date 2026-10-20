import 'package:david/src/data/case_packs.dart';
import 'package:david/src/domain/models.dart';
import 'package:david/src/retrieval/evidence_index.dart';
import 'package:david/src/retrieval/text_match.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('negation blocks a phrase that only appears under no or not', () {
    expect(
      phraseMatches(
        'The vendor reports no integration defect and no sensor dropout.',
        'integration defect',
      ),
      isFalse,
    );
    expect(
      phraseMatches(
        'The file does not contain a new contract with an independent buyer.',
        'new contract',
      ),
      isFalse,
    );
    expect(
      phraseMatches(
        'Addendum 7 authorizes bill-and-hold for the customer.',
        'bill-and-hold',
      ),
      isTrue,
    );
  });

  test(
    'acetylene search returns the harbor gas reading and respects modality',
    () {
      final harbor = CasePacks.byId('harbor-substation-4');
      final index = EvidenceIndex(harbor.evidence);

      final hits = index.search(
        const RetrievalQuery(text: 'acetylene', limit: 5),
      );
      expect(hits, isNotEmpty);
      expect(hits.first.unit.text, contains('42 ppm'));
      expect(hits.every((hit) => hit.unit.modality == 'dissolved-gas'), isTrue);

      final thermal = index.search(
        const RetrievalQuery(text: 'acetylene', modality: 'thermal', limit: 5),
      );
      expect(thermal, isEmpty);
    },
  );

  test('related party search hits the northline payment memo', () {
    final northline = CasePacks.byId('northline-logistics');
    final index = EvidenceIndex(northline.evidence);
    final hits = index.search(
      const RetrievalQuery(
        text: 'related party',
        sourceKind: SourceKind.record,
        limit: 4,
      ),
    );
    expect(hits.map((hit) => hit.unit.id), contains('n-related'));
  });

  test('blank query browses newest evidence with a zero score', () {
    final vault = CasePacks.byId('vault-c12');
    final index = EvidenceIndex(vault.evidence);
    final hits = index.search(const RetrievalQuery(text: '   ', limit: 3));
    expect(hits, hasLength(3));
    expect(hits.every((hit) => hit.score == 0), isTrue);
    expect(
      hits.first.unit.observedAt.isAfter(hits.last.unit.observedAt),
      isTrue,
    );
  });
}
