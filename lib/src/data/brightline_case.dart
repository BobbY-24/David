import '../domain/models.dart';
import 'builders.dart';

const _caseId = 'brightline-supply';
const _site = 'Brightline Supply vendor file';

/// Vendor check. The brief already names every pass, so it runs as one batch.
Engagement brightlineCase() {
  final evidence = <EvidenceUnit>[
    record(
      id: 'b-registry',
      caseId: _caseId,
      title: 'State registry entry',
      text: 'The state registry lists Brightline Supply LLC as active, formed in 2016. Annual reports filed on time every year.',
      observedAt: utc(2026, 9, 2, 14),
      site: _site,
      modality: 'registry',
      source: 'Secretary of State extract',
      collector: 'Owner',
    ),
    record(
      id: 'b-sanctions',
      caseId: _caseId,
      title: 'Sanctions screen',
      text: 'Sanctions screen of Brightline Supply LLC and its two owners against the OFAC SDN and consolidated lists returned no hit.',
      observedAt: utc(2026, 9, 2, 14, 10),
      site: _site,
      modality: 'sanctions',
      source: 'OFAC list snapshot 2026-09-01',
      collector: 'Owner',
    ),
    record(
      id: 'b-reviews',
      caseId: _caseId,
      title: 'Customer reviews digest',
      text: 'Customer reviews mention late deliveries in peak season. Delivery delays averaged nine days in the fourth quarter. Product quality is rated well.',
      observedAt: utc(2026, 9, 3, 9),
      site: _site,
      modality: 'reviews',
      source: 'Public review sites',
      collector: 'Owner',
    ),
    record(
      id: 'b-bank',
      caseId: _caseId,
      title: 'Bank reference',
      text: 'The bank reference confirms a business account open for eight years and in good standing.',
      observedAt: utc(2026, 9, 4, 11),
      site: _site,
      modality: 'banking',
      source: 'Bank reference letter',
      collector: 'Vendor',
    ),
    record(
      id: 'b-court',
      caseId: _caseId,
      title: 'Court record search',
      text: 'One small-claims case from 2025 over a late delivery, settled before trial. No other civil or criminal cases.',
      observedAt: utc(2026, 9, 4, 15),
      site: _site,
      modality: 'litigation',
      source: 'County court index',
      collector: 'Owner',
    ),
    record(
      id: 'b-liens',
      caseId: _caseId,
      title: 'UCC and lien search',
      text: 'The UCC search shows no tax lien and one equipment lease filing from 2023.',
      observedAt: utc(2026, 9, 4, 15, 30),
      site: _site,
      modality: 'liens',
      source: 'State UCC search',
      collector: 'Owner',
    ),
    ...metricSeries(
      caseId: _caseId,
      idPrefix: 'b-ontime',
      seriesId: 'on-time',
      title: 'On-time delivery rate',
      modality: 'delivery',
      source: 'Vendor scorecard',
      site: _site,
      unit: '% on time',
      collector: 'Vendor',
      readings: [
        MetricPoint(utc(2025, 12, 31, 18), 96),
        MetricPoint(utc(2026, 3, 31, 18), 94),
        MetricPoint(utc(2026, 6, 30, 18), 90),
        MetricPoint(
          utc(2026, 8, 31, 18),
          81,
          claim: 'On-time delivery fell to 81 percent as peak orders arrived.',
        ),
      ],
    ),
  ];

  return Engagement(
    id: _caseId,
    dealType: DealType.vendor,
    title: 'Brightline Supply',
    subject: 'Packaging vendor, six-month contract',
    question: 'Should we prepay Brightline Supply 50 percent on a six-month packaging contract, and on what terms?',
    summary: 'A packaging vendor wants half of a six-month order up front. The owner has a registry extract, a sanctions screen, reviews, a bank reference, and court and lien searches, and needs to decide how much to prepay and what to put in the contract.',
    site: _site,
    openedAt: utc(2026, 9, 5, 9),
    decisionCriteria: const [
      'Confirm the vendor exists, is in good standing, and has no sanctions exposure.',
      'Size the prepayment to the delivery risk the record actually shows.',
      'Name the contract terms that would cap the downside.',
    ],
    expectedModalities: const [
      'registry',
      'sanctions',
      'reviews',
      'banking',
      'litigation',
    ],
    plan: const [
      PlannedQuery(
        purpose: 'Existence and standing',
        text: 'registry formed annual reports good standing',
      ),
      PlannedQuery(
        purpose: 'Sanctions exposure',
        text: 'sanctions OFAC screen owners',
        modality: 'sanctions',
      ),
      PlannedQuery(
        purpose: 'Delivery record',
        text: 'late deliveries delivery delays on time',
      ),
      PlannedQuery(
        purpose: 'Bank, courts, and liens',
        text: 'bank reference court case tax lien UCC',
        sourceKind: SourceKind.record,
      ),
    ],
    exampleQueries: const [
      'late deliveries',
      'good standing',
      'sanctions',
      'tax lien',
    ],
    evidence: evidence,
    riskQuestions: const [
      RiskQuestion(
        id: 'delivery-reliability',
        outcome: Decision.proceedWithConditions,
        title: 'Delivery reliability risk',
        statement: 'The vendor is real and solvent but misses delivery dates in peak season.',
        actionIfLead: 'Pay in milestones on delivery instead of 50 percent up front, and add a late-delivery credit to the contract.',
        support: [
          Signature('late deliveries', 1.4),
          Signature('delivery delays', 1),
          Signature('late delivery', 0.8),
        ],
        contradict: [Signature('on time delivery above', 1.2)],
      ),
      RiskQuestion(
        id: 'shell-or-fraud',
        outcome: Decision.walkAway,
        dealBreaker: true,
        title: 'Shell company or fraud',
        statement: 'The vendor is not a real operating business and the prepayment would be lost.',
        actionIfLead: 'Do not prepay. Ask for a site visit and a bank-verified account before any payment.',
        support: [
          Signature('mail drop address', 1.6),
          Signature('recently formed', 1.2),
          Signature('sanctions match', 2),
        ],
        contradict: [
          Signature('formed in 2016', 1.2),
          Signature('annual reports filed', 0.8),
        ],
      ),
      RiskQuestion(
        id: 'financial-distress',
        outcome: Decision.hold,
        title: 'Financial distress',
        statement: 'The vendor is short of cash and may not survive the contract term.',
        actionIfLead: 'Cap the prepayment at one month of orders and ask for a parent or personal guarantee.',
        support: [
          Signature('overdrawn', 1.4),
          Signature('tax lien', 1.4),
          Signature('missed payroll', 1.2),
        ],
        contradict: [Signature('good standing', 1.2)],
      ),
      RiskQuestion(
        id: 'clean-vendor',
        outcome: Decision.proceed,
        title: 'No material risk',
        statement: 'The vendor is established and reliable, so standard prepayment terms are fine.',
        actionIfLead: 'Proceed on the requested terms.',
        support: [
          Signature('good standing', 0.8),
          Signature('annual reports filed', 0.6),
        ],
        contradict: [
          Signature('late deliveries', 1),
          Signature('delivery delays', 0.8),
        ],
      ),
    ],
  );
}
