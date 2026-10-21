import '../domain/models.dart';

/// Limits that mirror `service/david_lab/specs.py`. The service enforces the
/// same rules; the desk checks them first so the editor can show a fix.
const maxChecks = 12;
const maxRisks = 8;
const minRisks = 2;
const maxCriteria = 8;
const maxQuestions = 10;
const maxDealBreakers = 10;

final _slug = RegExp(r'^[a-z][a-z0-9-]{1,39}$');

/// What a risk recommends, in the words the service stores.
enum SpecOutcome {
  proceed('proceed', 'Proceed'),
  proceedWithConditions('proceed_with_conditions', 'Proceed with conditions'),
  hold('hold', 'Hold'),
  walkAway('walk_away', 'Walk away');

  const SpecOutcome(this.wire, this.label);

  final String wire;
  final String label;

  Decision get decision => switch (this) {
    SpecOutcome.proceed => Decision.proceed,
    SpecOutcome.proceedWithConditions => Decision.proceedWithConditions,
    SpecOutcome.hold => Decision.hold,
    SpecOutcome.walkAway => Decision.walkAway,
  };

  static SpecOutcome fromWire(String? value) {
    return SpecOutcome.values.firstWhere(
      (outcome) => outcome.wire == value,
      orElse: () => SpecOutcome.hold,
    );
  }
}

enum SpecEvidenceKind {
  record('record', 'Record'),
  metric('metric', 'Metric');

  const SpecEvidenceKind(this.wire, this.label);

  final String wire;
  final String label;

  static SpecEvidenceKind fromWire(String? value) {
    return SpecEvidenceKind.values.firstWhere(
      (kind) => kind.wire == value,
      orElse: () => SpecEvidenceKind.record,
    );
  }
}

const _dealTypeWire = {
  DealType.customer: 'customer',
  DealType.vendor: 'vendor',
  DealType.partner: 'partner',
  DealType.contractor: 'contractor',
  DealType.acquisition: 'acquisition',
  DealType.lease: 'lease',
};

DealType dealTypeFromWire(String? value) {
  return _dealTypeWire.entries
      .firstWhere(
        (entry) => entry.value == value,
        orElse: () => const MapEntry(DealType.vendor, 'vendor'),
      )
      .key;
}

String dealTypeToWire(DealType type) => _dealTypeWire[type]!;

class SpecCheck {
  const SpecCheck({
    required this.title,
    required this.query,
    this.evidenceKind = SpecEvidenceKind.record,
  });

  factory SpecCheck.fromJson(Map<String, Object?> json) => SpecCheck(
    title: json['title'] as String? ?? '',
    query: json['query'] as String? ?? '',
    evidenceKind: SpecEvidenceKind.fromWire(json['evidence_kind'] as String?),
  );

  final String title;
  final String query;
  final SpecEvidenceKind evidenceKind;

  Map<String, Object?> toJson() => {
    'title': title,
    'query': query,
    'evidence_kind': evidenceKind.wire,
  };
}

class SpecRisk {
  const SpecRisk({
    required this.id,
    required this.title,
    required this.statement,
    this.outcome = SpecOutcome.hold,
    this.action = '',
    this.dealBreaker = false,
  });

  factory SpecRisk.fromJson(Map<String, Object?> json) => SpecRisk(
    id: json['id'] as String? ?? '',
    title: json['title'] as String? ?? '',
    statement: json['statement'] as String? ?? '',
    outcome: SpecOutcome.fromWire(json['outcome'] as String?),
    action: json['action'] as String? ?? '',
    dealBreaker: json['deal_breaker'] == true,
  );

  final String id;
  final String title;
  final String statement;
  final SpecOutcome outcome;
  final String action;
  final bool dealBreaker;

  SpecRisk copyWith({
    String? id,
    String? title,
    String? statement,
    SpecOutcome? outcome,
    String? action,
    bool? dealBreaker,
  }) => SpecRisk(
    id: id ?? this.id,
    title: title ?? this.title,
    statement: statement ?? this.statement,
    outcome: outcome ?? this.outcome,
    action: action ?? this.action,
    dealBreaker: dealBreaker ?? this.dealBreaker,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'statement': statement,
    'outcome': outcome.wire,
    'action': action,
    'deal_breaker': dealBreaker,
  };
}

class AgentSpec {
  const AgentSpec({
    required this.name,
    required this.dealType,
    required this.question,
    this.decisionCriteria = const [],
    required this.checks,
    required this.risks,
    this.questionsToAsk = const [],
  });

  factory AgentSpec.fromJson(Map<String, Object?> json) => AgentSpec(
    name: json['name'] as String? ?? '',
    dealType: dealTypeFromWire(json['deal_type'] as String?),
    question: json['question'] as String? ?? '',
    decisionCriteria: _strings(json['decision_criteria']),
    checks: [
      for (final item in (json['checks'] as List<Object?>? ?? const []))
        if (item is Map<String, Object?>) SpecCheck.fromJson(item),
    ],
    risks: [
      for (final item in (json['risks'] as List<Object?>? ?? const []))
        if (item is Map<String, Object?>) SpecRisk.fromJson(item),
    ],
    questionsToAsk: _strings(json['questions_to_ask']),
  );

  final String name;
  final DealType dealType;
  final String question;
  final List<String> decisionCriteria;
  final List<SpecCheck> checks;
  final List<SpecRisk> risks;
  final List<String> questionsToAsk;

  Map<String, Object?> toJson() => {
    'name': name,
    'deal_type': dealTypeToWire(dealType),
    'question': question,
    'decision_criteria': decisionCriteria,
    'checks': [for (final check in checks) check.toJson()],
    'risks': [for (final risk in risks) risk.toJson()],
    'questions_to_ask': questionsToAsk,
  };

  /// Problems in plain words, in the order a person would fix them. Empty when
  /// the spec can be saved. Mirrors the service's rules.
  List<String> problems() {
    final out = <String>[];
    if (name.trim().length < 2 || name.length > 120) {
      out.add('Give the spec a name of 2 to 120 characters.');
    }
    if (question.trim().length < 10 || question.length > 600) {
      out.add('The question must be 10 to 600 characters.');
    }
    if (checks.isEmpty || checks.length > maxChecks) {
      out.add('Add between 1 and $maxChecks checks.');
    }
    for (final check in checks) {
      if (check.title.trim().length < 2 || check.query.trim().length < 2) {
        out.add('Each check needs a title and a search phrase.');
        break;
      }
    }
    if (risks.length < minRisks || risks.length > maxRisks) {
      out.add('Add between $minRisks and $maxRisks risk questions.');
    }
    final ids = <String>{};
    for (final risk in risks) {
      if (!_slug.hasMatch(risk.id)) {
        out.add(
          'Risk "${risk.title}" needs an id of lowercase letters, digits and hyphens.',
        );
      } else if (!ids.add(risk.id)) {
        out.add('Risk ids must be unique: "${risk.id}" is used twice.');
      }
      if (risk.title.trim().length < 2) {
        out.add('Each risk needs a title.');
      }
      if (risk.statement.trim().length < 5) {
        out.add('Each risk needs a statement of at least 5 characters.');
      }
    }
    if (decisionCriteria.length > maxCriteria) {
      out.add('Keep decision criteria to $maxCriteria.');
    }
    if (questionsToAsk.length > maxQuestions) {
      out.add('Keep questions to ask to $maxQuestions.');
    }
    return out;
  }
}

class CompanyProfile {
  const CompanyProfile({
    this.companyName = '',
    this.industry = '',
    this.jurisdictions = '',
    this.currency = 'USD',
    this.maxExposure = 0,
    this.dealBreakers = const [],
  });

  factory CompanyProfile.fromJson(Map<String, Object?> json) => CompanyProfile(
    companyName: json['company_name'] as String? ?? '',
    industry: json['industry'] as String? ?? '',
    jurisdictions: json['jurisdictions'] as String? ?? '',
    currency: json['currency'] as String? ?? 'USD',
    maxExposure: (json['max_exposure'] as num?)?.toDouble() ?? 0,
    dealBreakers: _strings(json['deal_breakers']),
  );

  final String companyName;
  final String industry;
  final String jurisdictions;
  final String currency;
  final double maxExposure;
  final List<String> dealBreakers;

  Map<String, Object?> toJson() => {
    'company_name': companyName,
    'industry': industry,
    'jurisdictions': jurisdictions,
    'currency': currency,
    'max_exposure': maxExposure,
    'deal_breakers': dealBreakers,
    'standing_checks': <Object?>[],
  };

  List<String> problems() {
    final out = <String>[];
    if (!RegExp(r'^[A-Z]{3}$').hasMatch(currency)) {
      out.add('Currency is a three-letter code such as USD.');
    }
    if (maxExposure < 0) {
      out.add('Maximum exposure cannot be negative.');
    }
    if (dealBreakers.length > maxDealBreakers) {
      out.add('Keep deal-breakers to $maxDealBreakers.');
    }
    return out;
  }
}

/// A spec as the service stores it, with the version the run will pin.
class StoredSpec {
  const StoredSpec({
    required this.specId,
    required this.version,
    required this.hash,
    required this.spec,
  });

  factory StoredSpec.fromJson(Map<String, Object?> json) => StoredSpec(
    specId: json['spec_id'] as String? ?? '',
    version: (json['version'] as num?)?.toInt() ?? 1,
    hash: json['hash'] as String? ?? '',
    spec: AgentSpec.fromJson(
      (json['spec'] as Map<String, Object?>?) ?? const {},
    ),
  );

  final String specId;
  final int version;
  final String hash;
  final AgentSpec spec;
}

List<String> _strings(Object? value) => [
  for (final item in (value as List<Object?>? ?? const [])) item.toString(),
];
