import 'package:david/src/spec/models.dart';
import 'package:david/src/spec/templates.dart';
import 'package:flutter_test/flutter_test.dart';

AgentSpec valid() => starterTemplates.first;

void main() {
  test(
    'all six starter templates pass the same rules the service enforces',
    () {
      expect(starterTemplates, hasLength(6));
      for (final template in starterTemplates) {
        expect(template.problems(), isEmpty, reason: template.name);
      }
    },
  );

  test('a template survives a JSON round trip unchanged', () {
    for (final template in starterTemplates) {
      final again = AgentSpec.fromJson(template.toJson());
      expect(again.toJson(), template.toJson(), reason: template.name);
    }
  });

  test(
    'every template has at least one deal-breaker, so the rule is exercised',
    () {
      for (final template in starterTemplates) {
        expect(
          template.risks.any((risk) => risk.dealBreaker),
          isTrue,
          reason: template.name,
        );
      }
    },
  );

  test('a bad risk id is named, not silently fixed', () {
    final bad = AgentSpec(
      name: 'Bad',
      dealType: valid().dealType,
      question: 'Should we proceed with this one?',
      checks: valid().checks,
      risks: [
        const SpecRisk(
          id: 'Upper Case',
          title: 'One',
          statement: 'A statement here.',
        ),
        const SpecRisk(id: 'two', title: 'Two', statement: 'A statement here.'),
      ],
    );
    expect(bad.problems().join(' '), contains('lowercase letters'));
  });

  test(
    'duplicate risk ids, too few risks, and too many checks are refused',
    () {
      AgentSpec variant({List<SpecRisk>? risks, List<SpecCheck>? checks}) =>
          AgentSpec(
            name: 'Spec',
            dealType: valid().dealType,
            question: 'Should we proceed with this one?',
            checks: checks ?? valid().checks,
            risks: risks ?? valid().risks,
          );
      final duplicate = variant(
        risks: const [
          SpecRisk(id: 'same', title: 'One', statement: 'A statement here.'),
          SpecRisk(id: 'same', title: 'Two', statement: 'A statement here.'),
        ],
      );
      expect(duplicate.problems().join(' '), contains('used twice'));

      final single = variant(
        risks: const [
          SpecRisk(id: 'only', title: 'One', statement: 'A statement here.'),
        ],
      );
      expect(single.problems().join(' '), contains('between 2 and 8'));

      final crowded = variant(
        checks: List.filled(
          13,
          const SpecCheck(title: 'Check', query: 'phrase'),
        ),
      );
      expect(crowded.problems().join(' '), contains('between 1 and 12'));
    },
  );

  test('an empty question and an unknown deal type fall back safely', () {
    final spec = AgentSpec.fromJson({
      'name': 'Short',
      'deal_type': 'casino',
      'question': 'short',
      'checks': <Object?>[],
      'risks': <Object?>[],
    });
    expect(spec.dealType, isNotNull);
    expect(spec.problems(), isNotEmpty);
  });

  test(
    'a profile needs a three-letter currency and a non-negative exposure',
    () {
      expect(const CompanyProfile(currency: 'USD').problems(), isEmpty);
      expect(const CompanyProfile(currency: 'dollars').problems(), isNotEmpty);
      expect(const CompanyProfile(maxExposure: -5).problems(), isNotEmpty);
    },
  );

  test('outcomes map to the decisions the memo shows', () {
    expect(
      SpecOutcome.proceedWithConditions.decision.label,
      'Proceed with conditions',
    );
    expect(SpecOutcome.fromWire('walk_away'), SpecOutcome.walkAway);
    expect(SpecOutcome.fromWire('nonsense'), SpecOutcome.hold);
  });
}
