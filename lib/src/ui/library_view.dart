import 'package:flutter/material.dart';

import '../domain/models.dart';
import '../spec/models.dart';
import '../spec/templates.dart';
import '../state/desk_controller.dart';
import 'theme.dart';
import 'widgets.dart';

const libraryProfileSaveKey = ValueKey<String>('library-profile-save');
const libraryNewSpecKey = ValueKey<String>('library-new-spec');
const libraryEditorSaveKey = ValueKey<String>('library-editor-save');
const libraryEditorNameKey = ValueKey<String>('library-editor-name');

/// Where the user keeps their deal specs and company profile.
class LibraryView extends StatefulWidget {
  const LibraryView({super.key, required this.desk});

  final DeskController desk;

  @override
  State<LibraryView> createState() => _LibraryViewState();
}

class _LibraryViewState extends State<LibraryView> {
  _EditTarget? _target;

  void _open(AgentSpec spec, {String? specId, required String label}) {
    setState(
      () => _target = _EditTarget(spec: spec, specId: specId, label: label),
    );
  }

  @override
  Widget build(BuildContext context) {
    final desk = widget.desk;
    final target = _target;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      children: [
        const SectionLabel('Library'),
        const SizedBox(height: 8),
        const Text(
          'Your company profile and the agent specs you run. A spec is saved as numbered versions, and a run records the version it used.',
          style: TextStyle(color: DavidColors.muted, height: 1.45),
        ),
        const SizedBox(height: 16),
        if (desk.libraryError != null) ...[
          PanelCard(
            child: Text(
              desk.libraryError!,
              style: const TextStyle(color: DavidColors.negative, height: 1.4),
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (target != null)
          _SpecEditor(
            key: ValueKey(target.specId ?? 'new-${target.label}'),
            desk: desk,
            target: target,
            onDone: () => setState(() => _target = null),
          )
        else ...[
          _ProfileCard(desk: desk),
          const SizedBox(height: 16),
          const SectionLabel('Start from a template'),
          const SizedBox(height: 8),
          for (final template in starterTemplates)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: PanelCard(
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            template.name,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${formatDealTypeName(template.dealType)} · ${template.risks.length} risk questions',
                            style: const TextStyle(
                              color: DavidColors.muted,
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    OutlinedButton(
                      onPressed: () => _open(template, label: template.name),
                      child: const Text('Use'),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 16),
          const SectionLabel('Your specs'),
          const SizedBox(height: 8),
          if (desk.savedSpecs.isEmpty)
            const EmptyNote(
              title: 'No specs yet',
              body: 'Start from a template above. Each save becomes a numbered version you can run.',
            ),
          for (final stored in desk.savedSpecs)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: PanelCard(
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            stored.spec.name,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Version ${stored.version} · ${formatDealTypeName(stored.spec.dealType)} · ${stored.hash.substring(0, 8)}',
                            style: const TextStyle(
                              color: DavidColors.muted,
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    OutlinedButton(
                      onPressed: () => _open(
                        stored.spec,
                        specId: stored.specId,
                        label: '${stored.spec.name} v${stored.version + 1}',
                      ),
                      child: const Text('New version'),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ],
    );
  }
}

String formatDealTypeName(DealType type) {
  return switch (type) {
    DealType.customer => 'New customer',
    DealType.vendor => 'Vendor',
    DealType.partner => 'Partner',
    DealType.contractor => 'Contractor',
    DealType.acquisition => 'Acquisition',
    DealType.lease => 'Lease',
  };
}

class _EditTarget {
  const _EditTarget({required this.spec, this.specId, required this.label});

  final AgentSpec spec;
  final String? specId;
  final String label;
}

class _ProfileCard extends StatefulWidget {
  const _ProfileCard({required this.desk});

  final DeskController desk;

  @override
  State<_ProfileCard> createState() => _ProfileCardState();
}

class _ProfileCardState extends State<_ProfileCard> {
  late final TextEditingController _company;
  late final TextEditingController _industry;
  late final TextEditingController _jurisdictions;
  late final TextEditingController _currency;
  late final TextEditingController _exposure;
  late final TextEditingController _breakers;
  String? _error;

  @override
  void initState() {
    super.initState();
    final profile = widget.desk.companyProfile;
    _company = TextEditingController(text: profile.companyName);
    _industry = TextEditingController(text: profile.industry);
    _jurisdictions = TextEditingController(text: profile.jurisdictions);
    _currency = TextEditingController(text: profile.currency);
    _exposure = TextEditingController(
      text: profile.maxExposure == 0
          ? ''
          : profile.maxExposure.toStringAsFixed(0),
    );
    _breakers = TextEditingController(text: profile.dealBreakers.join('\n'));
  }

  @override
  void dispose() {
    for (final controller in [
      _company,
      _industry,
      _jurisdictions,
      _currency,
      _exposure,
      _breakers,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final profile = CompanyProfile(
      companyName: _company.text.trim(),
      industry: _industry.text.trim(),
      jurisdictions: _jurisdictions.text.trim(),
      currency: _currency.text.trim().toUpperCase(),
      maxExposure: double.tryParse(_exposure.text.trim()) ?? 0,
      dealBreakers: [
        for (final line in _breakers.text.split('\n'))
          if (line.trim().isNotEmpty) line.trim(),
      ],
    );
    final problem = await widget.desk.saveProfile(profile);
    if (mounted) {
      setState(() => _error = problem);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Company profile',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
          ),
          const SizedBox(height: 10),
          _field('Company name', _company),
          _field('Industry', _industry),
          _field('Jurisdictions', _jurisdictions),
          Row(
            children: [
              Expanded(child: _field('Currency', _currency)),
              const SizedBox(width: 10),
              Expanded(
                child: _field(
                  'Max exposure per counterparty',
                  _exposure,
                  number: true,
                ),
              ),
            ],
          ),
          _field('Deal-breakers (one per line)', _breakers, lines: 3),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                _error!,
                style: const TextStyle(color: DavidColors.negative),
              ),
            ),
          FilledButton(
            key: libraryProfileSaveKey,
            onPressed: widget.desk.libraryBusy ? null : _save,
            child: const Text('Save profile'),
          ),
        ],
      ),
    );
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    bool number = false,
    int lines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controller,
        minLines: lines,
        maxLines: lines,
        keyboardType: number ? TextInputType.number : null,
        decoration: InputDecoration(labelText: label),
      ),
    );
  }
}

class _CheckRow {
  _CheckRow(SpecCheck check)
    : title = TextEditingController(text: check.title),
      query = TextEditingController(text: check.query),
      kind = check.evidenceKind;

  final TextEditingController title;
  final TextEditingController query;
  SpecEvidenceKind kind;

  void dispose() {
    title.dispose();
    query.dispose();
  }
}

class _RiskRow {
  _RiskRow(SpecRisk risk)
    : id = TextEditingController(text: risk.id),
      title = TextEditingController(text: risk.title),
      statement = TextEditingController(text: risk.statement),
      action = TextEditingController(text: risk.action),
      outcome = risk.outcome,
      dealBreaker = risk.dealBreaker;

  final TextEditingController id;
  final TextEditingController title;
  final TextEditingController statement;
  final TextEditingController action;
  SpecOutcome outcome;
  bool dealBreaker;

  void dispose() {
    for (final controller in [id, title, statement, action]) {
      controller.dispose();
    }
  }
}

/// Edits one spec. Saving creates version 1 of a new spec, or the next version
/// of an existing one. Nothing is changed in place.
class _SpecEditor extends StatefulWidget {
  const _SpecEditor({
    super.key,
    required this.desk,
    required this.target,
    required this.onDone,
  });

  final DeskController desk;
  final _EditTarget target;
  final VoidCallback onDone;

  @override
  State<_SpecEditor> createState() => _SpecEditorState();
}

class _SpecEditorState extends State<_SpecEditor> {
  late final TextEditingController _name;
  late final TextEditingController _question;
  late final TextEditingController _criteria;
  late final TextEditingController _questions;
  late DealType _dealType;
  late final List<_CheckRow> _checks;
  late final List<_RiskRow> _risks;
  String? _error;

  @override
  void initState() {
    super.initState();
    final spec = widget.target.spec;
    _name = TextEditingController(text: spec.name);
    _question = TextEditingController(text: spec.question);
    _criteria = TextEditingController(text: spec.decisionCriteria.join('\n'));
    _questions = TextEditingController(text: spec.questionsToAsk.join('\n'));
    _dealType = spec.dealType;
    _checks = [for (final check in spec.checks) _CheckRow(check)];
    _risks = [for (final risk in spec.risks) _RiskRow(risk)];
  }

  @override
  void dispose() {
    for (final controller in [_name, _question, _criteria, _questions]) {
      controller.dispose();
    }
    for (final row in _checks) {
      row.dispose();
    }
    for (final row in _risks) {
      row.dispose();
    }
    super.dispose();
  }

  List<String> _lines(String text) => [
    for (final line in text.split('\n'))
      if (line.trim().isNotEmpty) line.trim(),
  ];

  AgentSpec _build() {
    return AgentSpec(
      name: _name.text.trim(),
      dealType: _dealType,
      question: _question.text.trim(),
      decisionCriteria: _lines(_criteria.text),
      checks: [
        for (final row in _checks)
          SpecCheck(
            title: row.title.text.trim(),
            query: row.query.text.trim(),
            evidenceKind: row.kind,
          ),
      ],
      risks: [
        for (final row in _risks)
          SpecRisk(
            id: row.id.text.trim(),
            title: row.title.text.trim(),
            statement: row.statement.text.trim(),
            outcome: row.outcome,
            action: row.action.text.trim(),
            dealBreaker: row.dealBreaker,
          ),
      ],
      questionsToAsk: _lines(_questions.text),
    );
  }

  Future<void> _save() async {
    final problem = await widget.desk.saveSpec(
      _build(),
      specId: widget.target.specId,
    );
    if (!mounted) {
      return;
    }
    if (problem == null) {
      widget.onDone();
    } else {
      setState(() => _error = problem);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isVersion = widget.target.specId != null;
    return PanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isVersion
                ? 'New version of ${widget.target.label.split(' v').first}'
                : 'New spec from ${widget.target.label}',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
          ),
          const SizedBox(height: 4),
          const Text(
            'Saving creates a new numbered version. Earlier versions stay as they were.',
            style: TextStyle(color: DavidColors.faint, fontSize: 12.5),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                _error!,
                style: const TextStyle(
                  color: DavidColors.negative,
                  height: 1.4,
                ),
              ),
            ),
          Wrap(
            spacing: 8,
            children: [
              FilledButton(
                key: libraryEditorSaveKey,
                onPressed: widget.desk.libraryBusy ? null : _save,
                child: Text(isVersion ? 'Save new version' : 'Save spec'),
              ),
              OutlinedButton(
                onPressed: widget.onDone,
                child: const Text('Cancel'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            key: libraryEditorNameKey,
            controller: _name,
            decoration: const InputDecoration(labelText: 'Name'),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<DealType>(
            initialValue: _dealType,
            decoration: const InputDecoration(labelText: 'Deal type'),
            items: [
              for (final type in DealType.values)
                DropdownMenuItem(
                  value: type,
                  child: Text(formatDealTypeName(type)),
                ),
            ],
            onChanged: (value) =>
                setState(() => _dealType = value ?? _dealType),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _question,
            minLines: 2,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'The deal question'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _criteria,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Decision criteria (one per line)',
            ),
          ),
          const SizedBox(height: 16),
          const SectionLabel('Checks'),
          const SizedBox(height: 8),
          for (var i = 0; i < _checks.length; i++)
            _CheckEditor(
              row: _checks[i],
              onRemove: () => setState(() {
                _checks.removeAt(i).dispose();
              }),
              onChanged: () => setState(() {}),
            ),
          if (_checks.length < maxChecks)
            TextButton.icon(
              onPressed: () => setState(
                () => _checks.add(
                  _CheckRow(const SpecCheck(title: '', query: '')),
                ),
              ),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add check'),
            ),
          const SizedBox(height: 16),
          const SectionLabel('Risk questions'),
          const SizedBox(height: 8),
          for (var i = 0; i < _risks.length; i++)
            _RiskEditor(
              row: _risks[i],
              onRemove: () => setState(() {
                _risks.removeAt(i).dispose();
              }),
              onChanged: () => setState(() {}),
            ),
          if (_risks.length < maxRisks)
            TextButton.icon(
              onPressed: () => setState(
                () => _risks.add(
                  _RiskRow(const SpecRisk(id: '', title: '', statement: '')),
                ),
              ),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add risk question'),
            ),
          const SizedBox(height: 16),
          TextField(
            controller: _questions,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Questions to ask the counterparty (one per line)',
            ),
          ),
        ],
      ),
    );
  }
}

class _CheckEditor extends StatelessWidget {
  const _CheckEditor({
    required this.row,
    required this.onRemove,
    required this.onChanged,
  });

  final _CheckRow row;
  final VoidCallback onRemove;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: row.title,
                  decoration: const InputDecoration(labelText: 'Check'),
                  onChanged: (_) => onChanged(),
                ),
              ),
              IconButton(
                onPressed: onRemove,
                icon: const Icon(Icons.close, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: row.query,
                  decoration: const InputDecoration(labelText: 'Search for'),
                  onChanged: (_) => onChanged(),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 170,
                child: DropdownButtonFormField<SpecEvidenceKind>(
                  initialValue: row.kind,
                  decoration: const InputDecoration(labelText: 'Kind'),
                  items: [
                    for (final kind in SpecEvidenceKind.values)
                      DropdownMenuItem(value: kind, child: Text(kind.label)),
                  ],
                  onChanged: (value) {
                    row.kind = value ?? row.kind;
                    onChanged();
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RiskEditor extends StatelessWidget {
  const _RiskEditor({
    required this.row,
    required this.onRemove,
    required this.onChanged,
  });

  final _RiskRow row;
  final VoidCallback onRemove;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: DavidColors.line),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: row.title,
                    decoration: const InputDecoration(labelText: 'Risk'),
                    onChanged: (_) => onChanged(),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 150,
                  child: TextField(
                    controller: row.id,
                    decoration: const InputDecoration(labelText: 'Id'),
                    onChanged: (_) => onChanged(),
                  ),
                ),
                IconButton(
                  onPressed: onRemove,
                  icon: const Icon(Icons.close, size: 18),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: row.statement,
              minLines: 1,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'What would be true if this risk is real',
              ),
              onChanged: (_) => onChanged(),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: row.action,
              decoration: const InputDecoration(
                labelText: 'Action if this risk leads',
              ),
              onChanged: (_) => onChanged(),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<SpecOutcome>(
                    initialValue: row.outcome,
                    decoration: const InputDecoration(labelText: 'Recommends'),
                    items: [
                      for (final outcome in SpecOutcome.values)
                        DropdownMenuItem(
                          value: outcome,
                          child: Text(outcome.label),
                        ),
                    ],
                    onChanged: (value) {
                      row.outcome = value ?? row.outcome;
                      onChanged();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Switch(
                  value: row.dealBreaker,
                  activeThumbColor: DavidColors.negative,
                  onChanged: (value) {
                    row.dealBreaker = value;
                    onChanged();
                  },
                ),
                const Text(
                  'Deal-breaker',
                  style: TextStyle(color: DavidColors.muted),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
