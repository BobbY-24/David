import 'package:david/src/data/engagement_packs.dart';
import 'package:david/src/domain/models.dart';
import 'package:david/src/retrieval/evidence_index.dart';
import 'package:david/src/retrieval/text_match.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('negation blocks a phrase that only appears under no or not', () {
    expect(
      phraseMatches(
        'The vendor reports no integration defect and no device dropout.',
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

  test('sanctions search returns the screen and respects modality', () {
    final brightline = EngagementPacks.byId('brightline-supply');
    final index = EvidenceIndex(brightline.evidence);

    final hits = index.search(
      const RetrievalQuery(text: 'OFAC sanctions', limit: 5),
    );
    expect(hits, isNotEmpty);
    expect(hits.first.unit.id, 'b-sanctions');

    final reviews = index.search(
      const RetrievalQuery(
        text: 'OFAC sanctions',
        modality: 'reviews',
        limit: 5,
      ),
    );
    expect(reviews, isEmpty);
  });

  test('related party search hits the northline payment memo', () {
    final northline = EngagementPacks.byId('northline-logistics');
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
    final corvid = EngagementPacks.byId('corvid-retail');
    final index = EvidenceIndex(corvid.evidence);
    final hits = index.search(const RetrievalQuery(text: '   ', limit: 3));
    expect(hits, hasLength(3));
    expect(hits.every((hit) => hit.score == 0), isTrue);
    expect(
      hits.first.unit.observedAt.isAfter(hits.last.unit.observedAt),
      isTrue,
    );
  });
}
