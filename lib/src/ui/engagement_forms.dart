import 'package:flutter/material.dart';

import '../spec/models.dart';
import '../state/desk_controller.dart';
import 'theme.dart';
import 'widgets.dart';

const newEngagementCreateKey = ValueKey<String>('new-engagement-create');
const evidenceAddKey = ValueKey<String>('evidence-add');
const evidenceTextKey = ValueKey<String>('evidence-text');

/// Starts a user engagement from one of the user's saved specs.
class NewEngagementView extends StatefulWidget {
  const NewEngagementView({super.key, required this.desk});

  final DeskController desk;

  @override
  State<NewEngagementView> createState() => _NewEngagementViewState();
}

class _NewEngagementViewState extends State<NewEngagementView> {
  final _counterparty = TextEditingController();
  final _value = TextEditingController();
  final _jurisdiction = TextEditingController();
  final _website = TextEditingController();
  final _context = TextEditingController();
  String? _specId;
  String? _error;

  @override
  void dispose() {
    for (final controller in [
      _counterparty,
      _value,
      _jurisdiction,
      _website,
      _context,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  StoredSpec? get _chosen {
    for (final stored in widget.desk.savedSpecs) {
      if (stored.specId == _specId) {
        return stored;
      }
    }
    return null;
  }

  Future<void> _create() async {
    final spec = _chosen;
    if (spec == null) {
      setState(() => _error = 'Choose a spec to run.');
      return;
    }
    final problem = await widget.desk.createEngagement({
      'spec_id': spec.specId,
      'spec_version': spec.version,
      'counterparty': _counterparty.text.trim(),
      'deal_value': double.tryParse(_value.text.trim()) ?? 0,
      'jurisdiction': _jurisdiction.text.trim(),
      'website': _website.text.trim(),
      'context': _context.text.trim(),
    });
    if (mounted) {
      setState(() => _error = problem);
    }
  }

  @override
  Widget build(BuildContext context) {
    final desk = widget.desk;
    final specs = desk.savedSpecs;
    if (specs.isEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        children: [
          const EmptyNote(
            title: 'Create a spec first',
            body: 'A user engagement runs a spec you saved in the Library, on your own Claude key.',
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () {
              desk.closeNewEngagement();
              desk.selectTab(DeskTab.library);
            },
            child: const Text('Open the Library'),
          ),
        ],
      );
    }
    _specId ??= specs.first.specId;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      children: [
        const SectionLabel('New engagement'),
        const SizedBox(height: 8),
        const Text(
          'Pick a spec, then describe the counterparty. The engagement pins the spec version you choose, so the memo can be traced to it.',
          style: TextStyle(color: DavidColors.muted, height: 1.45),
        ),
        const SizedBox(height: 16),
        PanelCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _specId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Spec'),
                items: [
                  for (final stored in specs)
                    DropdownMenuItem(
                      value: stored.specId,
                      child: Text('${stored.spec.name} · v${stored.version}'),
                    ),
                ],
                onChanged: (value) => setState(() => _specId = value),
              ),
              const SizedBox(height: 12),
              _field('Counterparty', _counterparty),
              _field('Deal value', _value, number: true),
              _field('Jurisdiction', _jurisdiction),
              _field('Website', _website),
              _field('Context', _context, lines: 3),
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
                    key: newEngagementCreateKey,
                    onPressed: desk.libraryBusy ? null : _create,
                    child: const Text('Create engagement'),
                  ),
                  OutlinedButton(
                    onPressed: desk.closeNewEngagement,
                    child: const Text('Cancel'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
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

/// Adds one pasted unit to the current user engagement.
class AddEvidenceCard extends StatefulWidget {
  const AddEvidenceCard({super.key, required this.desk});

  final DeskController desk;

  @override
  State<AddEvidenceCard> createState() => _AddEvidenceCardState();
}

class _AddEvidenceCardState extends State<AddEvidenceCard> {
  final _title = TextEditingController();
  final _source = TextEditingController();
  final _observed = TextEditingController();
  final _text = TextEditingController();
  SpecEvidenceKind _kind = SpecEvidenceKind.record;
  String? _error;

  @override
  void dispose() {
    for (final controller in [_title, _source, _observed, _text]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _add() async {
    final problem = await widget.desk.addEvidence({
      'title': _title.text.trim(),
      'source': _source.text.trim(),
      'kind': _kind.wire,
      'observed_at': _observed.text.trim(),
      'text': _text.text.trim(),
    });
    if (!mounted) {
      return;
    }
    setState(() => _error = problem);
    if (problem == null) {
      for (final controller in [_title, _source, _observed, _text]) {
        controller.clear();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Add evidence',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
          ),
          const SizedBox(height: 4),
          const Text(
            'Paste the record. It is encrypted on the job service. Text that tries to instruct the model is quarantined and never sent to it.',
            style: TextStyle(
              color: DavidColors.faint,
              fontSize: 12.5,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _title,
            decoration: const InputDecoration(labelText: 'Title'),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _source,
                  decoration: const InputDecoration(labelText: 'Source'),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 170,
                child: DropdownButtonFormField<SpecEvidenceKind>(
                  initialValue: _kind,
                  decoration: const InputDecoration(labelText: 'Kind'),
                  items: [
                    for (final kind in SpecEvidenceKind.values)
                      DropdownMenuItem(value: kind, child: Text(kind.label)),
                  ],
                  onChanged: (value) => setState(() => _kind = value ?? _kind),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _observed,
            decoration: const InputDecoration(
              labelText: 'Observed on (for example 2026-10-01)',
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            key: evidenceTextKey,
            controller: _text,
            minLines: 3,
            maxLines: 6,
            decoration: const InputDecoration(labelText: 'Text'),
          ),
          const SizedBox(height: 12),
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
          FilledButton(
            key: evidenceAddKey,
            onPressed: widget.desk.libraryBusy ? null : _add,
            child: const Text('Add evidence'),
          ),
        ],
      ),
    );
  }
}
