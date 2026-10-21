import '../domain/models.dart';
import 'models.dart';

/// The six starting points. A user clones one, then edits it. Each one passes
/// [AgentSpec.problems] and is tested that way.
final List<AgentSpec> starterTemplates = [
  AgentSpec(
    name: 'New wholesale customer',
    dealType: DealType.customer,
    question:
        'Should we ship a first order to this customer on the terms requested?',
    decisionCriteria: const [
      'Identify the legal entity that would owe the invoice.',
      'Judge payment risk from payment history, not from references alone.',
    ],
    checks: const [
      SpecCheck(
        title: 'Registry status',
        query: 'registry status dissolved active',
      ),
      SpecCheck(title: 'Sanctions screen', query: 'sanctions screen owners'),
      SpecCheck(
        title: 'Payment history',
        query: 'days beyond terms paid',
        evidenceKind: SpecEvidenceKind.metric,
      ),
      SpecCheck(
        title: 'Trade references',
        query: 'trade reference paid within terms',
      ),
    ],
    risks: const [
      SpecRisk(
        id: 'successor-entity',
        title: 'Trading through a successor entity',
        statement: 'The business now trades through a new entity after the old one was dissolved.',
        outcome: SpecOutcome.proceedWithConditions,
        action:
            'Contract with the exact legal name of the entity that will pay.',
      ),
      SpecRisk(
        id: 'phoenix-company',
        title: 'Phoenix company',
        statement:
            'The owners dissolved the company to leave creditors unpaid.',
        outcome: SpecOutcome.walkAway,
        dealBreaker: true,
      ),
      SpecRisk(
        id: 'slow-payer',
        title: 'Pays well beyond terms',
        statement: 'The customer pays well beyond agreed terms.',
        outcome: SpecOutcome.proceedWithConditions,
        action: 'Offer 30-day terms and take a deposit on the first order.',
      ),
      SpecRisk(
        id: 'sanctions-hit',
        title: 'Sanctions exposure',
        statement: 'The customer or an owner appears on a sanctions list.',
        outcome: SpecOutcome.walkAway,
        dealBreaker: true,
      ),
    ],
    questionsToAsk: const [
      'Which legal entity will be invoiced and will sign?',
      'Who guarantees payment if the order is large?',
    ],
  ),
  AgentSpec(
    name: 'Vendor check',
    dealType: DealType.vendor,
    question: 'Should we prepay this supplier, and on what terms?',
    decisionCriteria: const [
      'Confirm the supplier exists, is in good standing, and has no sanctions exposure.',
      'Size any prepayment to the delivery risk the records show.',
    ],
    checks: const [
      SpecCheck(
        title: 'Registry status',
        query: 'registry good standing active',
      ),
      SpecCheck(title: 'Sanctions screen', query: 'sanctions screen owners'),
      SpecCheck(title: 'Delivery record', query: 'late delivery on time'),
      SpecCheck(
        title: 'Bank and liens',
        query: 'bank reference lien court case',
      ),
    ],
    risks: const [
      SpecRisk(
        id: 'delivery-reliability',
        title: 'Delivery reliability',
        statement:
            'The supplier misses delivery dates, especially in peak periods.',
        outcome: SpecOutcome.proceedWithConditions,
        action: 'Pay in milestones on delivery and add a late-delivery credit.',
      ),
      SpecRisk(
        id: 'shell-or-fraud',
        title: 'Shell company or fraud',
        statement: 'The supplier is not an operating business, and a prepayment would be lost.',
        outcome: SpecOutcome.walkAway,
        dealBreaker: true,
      ),
      SpecRisk(
        id: 'financial-distress',
        title: 'Financial distress',
        statement: 'The supplier is short of cash and may not survive the contract term.',
        outcome: SpecOutcome.hold,
      ),
      SpecRisk(
        id: 'sanctions-hit',
        title: 'Sanctions exposure',
        statement: 'The supplier or an owner appears on a sanctions list.',
        outcome: SpecOutcome.walkAway,
        dealBreaker: true,
      ),
    ],
    questionsToAsk: const [
      'Can the supplier show a bank-verified account in its own name?',
      'Will the supplier accept milestone payments?',
    ],
  ),
  AgentSpec(
    name: 'Partner or reseller',
    dealType: DealType.partner,
    question: 'Should we sign this partner or reseller agreement?',
    decisionCriteria: const [
      'Check that the partner is who it says it is and has no conflict with our customers.',
      'Check that its public record would not damage our brand.',
    ],
    checks: const [
      SpecCheck(title: 'Registry status', query: 'registry active owners'),
      SpecCheck(title: 'Sanctions screen', query: 'sanctions screen owners'),
      SpecCheck(title: 'Public reputation', query: 'complaint lawsuit reviews'),
      SpecCheck(title: 'Litigation', query: 'lawsuit court case filed'),
    ],
    risks: const [
      SpecRisk(
        id: 'conflict-of-interest',
        title: 'Conflict with our customers',
        statement: 'The partner also serves a direct competitor or a shared customer on conflicting terms.',
        outcome: SpecOutcome.hold,
      ),
      SpecRisk(
        id: 'brand-risk',
        title: 'Brand risk',
        statement:
            'The partner has a public record of complaints or misconduct.',
        outcome: SpecOutcome.proceedWithConditions,
        action: 'Add a brand-standards clause with a termination right.',
      ),
      SpecRisk(
        id: 'pending-litigation',
        title: 'Pending litigation',
        statement:
            'The partner is a party to active litigation that could reach us.',
        outcome: SpecOutcome.proceedWithConditions,
        action: 'Add an indemnity and a right to pause referrals.',
      ),
      SpecRisk(
        id: 'sanctions-hit',
        title: 'Sanctions exposure',
        statement: 'The partner or an owner appears on a sanctions list.',
        outcome: SpecOutcome.walkAway,
        dealBreaker: true,
      ),
    ],
    questionsToAsk: const [
      'Which customers does the partner serve in our market?',
      'Who is the accountable owner for compliance?',
    ],
  ),
  AgentSpec(
    name: 'Contractor or freelancer business',
    dealType: DealType.contractor,
    question: 'Should we hire this contractor business for the work described?',
    decisionCriteria: const [
      'Check that the business is registered, licensed for the work, and insured.',
      'Check for past disputes that show how the work ended.',
    ],
    checks: const [
      SpecCheck(title: 'Registry status', query: 'registry active licence'),
      SpecCheck(
        title: 'Licence and insurance',
        query: 'licence insurance certificate expired',
      ),
      SpecCheck(
        title: 'Past disputes',
        query: 'dispute complaint claim settled',
      ),
      SpecCheck(title: 'References', query: 'reference completed on time'),
    ],
    risks: const [
      SpecRisk(
        id: 'unlicensed-work',
        title: 'No valid licence for the work',
        statement: 'The business cannot show a valid licence or insurance for this work.',
        outcome: SpecOutcome.walkAway,
        dealBreaker: true,
      ),
      SpecRisk(
        id: 'insurance-lapsed',
        title: 'Insurance lapsed',
        statement: 'Insurance has expired or does not cover the work.',
        outcome: SpecOutcome.hold,
      ),
      SpecRisk(
        id: 'past-disputes',
        title: 'Past disputes',
        statement: 'The business has disputes or claims that ended badly.',
        outcome: SpecOutcome.proceedWithConditions,
        action: 'Pay on completed milestones and hold back a retention amount.',
      ),
    ],
    questionsToAsk: const [
      'Can you share the current certificate of insurance?',
      'Who on your team will supervise the work?',
    ],
  ),
  AgentSpec(
    name: 'Acquisition target',
    dealType: DealType.acquisition,
    question: 'Should we proceed with acquiring this business, and at what price and terms?',
    decisionCriteria: const [
      'Confirm the revenue for the latest quarter against cash and physical activity.',
      'Confirm ownership and that no liens or undisclosed claims sit on the business.',
    ],
    checks: const [
      SpecCheck(
        title: 'Revenue against cash',
        query: 'revenue collections lag',
      ),
      SpecCheck(
        title: 'Related parties',
        query: 'related party registered agent',
      ),
      SpecCheck(
        title: 'Ownership and liens',
        query: 'owner lien ucc registered',
      ),
      SpecCheck(title: 'Litigation', query: 'lawsuit claim court pending'),
    ],
    risks: const [
      SpecRisk(
        id: 'related-party-revenue',
        title: 'Revenue from a related party',
        statement: 'A large share of revenue comes from a customer tied to the seller.',
        outcome: SpecOutcome.proceedWithConditions,
        action:
            'Hold part of the price in escrow until independent customers pay.',
      ),
      SpecRisk(
        id: 'revenue-quality',
        title: 'Revenue quality',
        statement:
            'Reported revenue is not matched by cash collections or activity.',
        outcome: SpecOutcome.hold,
      ),
      SpecRisk(
        id: 'undisclosed-claims',
        title: 'Undisclosed claims',
        statement:
            'Litigation or claims exist that the seller has not disclosed.',
        outcome: SpecOutcome.proceedWithConditions,
        action: 'Add a specific indemnity for the claims found.',
      ),
      SpecRisk(
        id: 'ownership-unclear',
        title: 'Ownership or liens unclear',
        statement: 'Ownership cannot be confirmed, or a lien secures the assets being bought.',
        outcome: SpecOutcome.walkAway,
        dealBreaker: true,
      ),
    ],
    questionsToAsk: const [
      'Who are the top five customers and are any of them related?',
      'What claims or disputes has the seller disclosed in writing?',
    ],
  ),
  AgentSpec(
    name: 'Lease or landlord',
    dealType: DealType.lease,
    question:
        'Should we sign this lease, and what protections must it include?',
    decisionCriteria: const [
      'Confirm that the landlord owns or controls the property.',
      'Confirm that the property has no liens or disputes that could cost us the space.',
    ],
    checks: const [
      SpecCheck(title: 'Ownership record', query: 'owner property deed title'),
      SpecCheck(title: 'Liens', query: 'lien mortgage judgment'),
      SpecCheck(title: 'Disputes', query: 'dispute violation complaint'),
      SpecCheck(title: 'Deposit history', query: 'deposit returned withheld'),
    ],
    risks: const [
      SpecRisk(
        id: 'landlord-authority',
        title: 'Landlord cannot show authority',
        statement: 'The person offering the lease cannot show they own or control the property.',
        outcome: SpecOutcome.walkAway,
        dealBreaker: true,
      ),
      SpecRisk(
        id: 'property-disputes',
        title: 'Property disputes',
        statement: 'The property has code violations or disputes that could disrupt us.',
        outcome: SpecOutcome.proceedWithConditions,
        action: 'Require the landlord to cure violations before occupancy.',
      ),
      SpecRisk(
        id: 'deposit-risk',
        title: 'Deposit at risk',
        statement: 'The landlord has a history of withholding deposits.',
        outcome: SpecOutcome.proceedWithConditions,
        action: 'Use an escrowed deposit with a written return schedule.',
      ),
    ],
    questionsToAsk: const [
      'Can you show the recorded deed or a signed authority from the owner?',
      'Are there any liens on the property?',
    ],
  ),
];
