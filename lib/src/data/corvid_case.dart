import '../domain/models.dart';
import 'builders.dart';

const _caseId = 'corvid-retail';
const _site = 'Corvid Retail credit file';

/// New-customer credit check. The records conflict, so the next search
/// depends on what is still missing.
Engagement corvidCase() {
  final evidence = <EvidenceUnit>[
    record(
      id: 'c-registry',
      caseId: _caseId,
      title: 'State registry entry',
      text: 'The state registry lists Corvid Retail LLC as dissolved in June 2025.',
      observedAt: utc(2026, 10, 1, 10),
      site: _site,
      modality: 'registry',
      source: 'Secretary of State extract',
      collector: 'Owner',
    ),
    record(
      id: 'c-successor',
      caseId: _caseId,
      title: 'Successor registration',
      text: 'A new entity, Corvid Retail Holdings LLC, registered in July 2025 at the same address and with the same manager.',
      observedAt: utc(2026, 10, 1, 10, 20),
      site: _site,
      modality: 'registry',
      source: 'Secretary of State extract',
      collector: 'Owner',
    ),
    record(
      id: 'c-web',
      caseId: _caseId,
      title: 'Website snapshot',
      text: 'The Corvid Retail website shows orders shipped last week and lists the same address as the registry.',
      observedAt: utc(2026, 10, 2, 9),
      site: _site,
      modality: 'website',
      source: 'Website capture',
      collector: 'Owner',
    ),
    record(
      id: 'c-refs',
      caseId: _caseId,
      title: 'Trade references',
      text: 'Two trade references say invoices were paid within terms in 2026.',
      observedAt: utc(2026, 10, 3, 15),
      site: _site,
      modality: 'references',
      source: 'Reference calls',
      collector: 'Owner',
    ),
    record(
      id: 'c-ucc',
      caseId: _caseId,
      title: 'UCC search',
      text: 'The UCC search shows a blanket lien held by Keystone Capital, filed against Corvid Retail Holdings in August 2025.',
      observedAt: utc(2026, 10, 3, 16),
      site: _site,
      modality: 'liens',
      source: 'State UCC search',
      collector: 'Owner',
    ),
    ...metricSeries(
      caseId: _caseId,
      idPrefix: 'c-dbt',
      seriesId: 'days-beyond-terms',
      title: 'Days beyond terms',
      modality: 'payments',
      source: 'Trade credit report',
      site: _site,
      unit: 'days',
      collector: 'Credit bureau',
      readings: [
        MetricPoint(utc(2025, 12, 31, 18), 12),
        MetricPoint(utc(2026, 3, 31, 18), 18),
        MetricPoint(utc(2026, 6, 30, 18), 30),
        MetricPoint(
          utc(2026, 9, 30, 18),
          45,
          claim: 'Payment history shows invoices 45 days beyond terms in the latest quarter.',
        ),
      ],
    ),
  ];

  return Engagement(
    id: _caseId,
    dealType: DealType.customer,
    title: 'Corvid Retail',
    subject: 'New wholesale customer, first order',
    question: 'Records conflict on whether Corvid Retail is still trading. Should we ship a 40,000 dollar first order on 60-day terms?',
    summary: 'A new retail customer wants 60-day terms on a first order. The registry says the company dissolved, but its website shows recent shipments and references say it pays. The owner needs to know who they would actually be selling to, and on what terms.',
    site: _site,
    openedAt: utc(2026, 10, 4, 9),
    decisionCriteria: const [
      'Identify the legal entity that would sign and owe the invoice.',
      'Judge payment risk from the payment record, not from references alone.',
      'Say what terms or guarantees would make the order safe.',
    ],
    expectedModalities: const [
      'registry',
      'website',
      'references',
      'liens',
      'payments',
    ],
    plan: const [
      PlannedQuery(
        purpose: 'Which entity exists',
        text: 'registry dissolved new entity same address',
        modality: 'registry',
      ),
      PlannedQuery(
        purpose: 'Payment behavior',
        text: 'paid within terms beyond terms',
      ),
    ],
    exampleQueries: const [
      'dissolved',
      'new entity',
      'beyond terms',
      'blanket lien',
    ],
    evidence: evidence,
    riskQuestions: const [
      RiskQuestion(
        id: 'successor-entity',
        title: 'Trading through a successor entity',
        statement: 'The old company dissolved and the business now trades through a new entity at the same address.',
        actionIfLead: 'Contract with Corvid Retail Holdings LLC by its exact legal name, take a personal guarantee from the manager, and start on 30-day terms with a credit limit.',
        support: [
          Signature('new entity', 1.2),
          Signature('same address', 1),
          Signature('dissolved', 0.8),
        ],
        contradict: [Signature('still active', 1.4)],
      ),
      RiskQuestion(
        id: 'phoenix-fraud',
        title: 'Phoenix company',
        statement: 'The owners dissolved the company to walk away from its debts and restarted under a new name.',
        actionIfLead:
            'Do not extend terms. Ship only against payment in advance.',
        support: [
          Signature('dissolved', 0.8),
          Signature('unpaid creditors', 1.6),
          Signature('blanket lien', 0.6),
        ],
        contradict: [Signature('paid within terms', 1.4)],
      ),
      RiskQuestion(
        id: 'slow-payer',
        title: 'Slow payer',
        statement: 'The customer is real but pays well beyond terms.',
        actionIfLead: 'Offer 30-day terms with a late fee, or a deposit on the first order.',
        support: [
          Signature('beyond terms', 1.2),
          Signature('blanket lien', 0.6),
        ],
        contradict: [Signature('paid within terms', 0.8)],
      ),
      RiskQuestion(
        id: 'healthy-customer',
        title: 'Healthy customer',
        statement: 'The customer is established and pays on time, so 60-day terms are fine.',
        actionIfLead: 'Ship on the requested terms.',
        support: [
          Signature('paid within terms', 1),
          Signature('orders shipped', 0.6),
        ],
        contradict: [Signature('dissolved', 1), Signature('beyond terms', 0.8)],
      ),
    ],
  );
}
