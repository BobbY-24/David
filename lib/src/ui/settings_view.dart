import 'package:flutter/material.dart';

import '../domain/format.dart';
import '../jobs/model_service.dart';
import '../state/desk_controller.dart';
import 'theme.dart';
import 'widgets.dart';

const settingsKeyFieldKey = ValueKey<String>('settings-key-field');
const settingsSaveKey = ValueKey<String>('settings-save-key');
const settingsVerifyKey = ValueKey<String>('settings-verify-key');
const settingsRemoveKey = ValueKey<String>('settings-remove-key');
const settingsUseClaudeKey = ValueKey<String>('settings-use-claude');
const settingsModelKey = ValueKey<String>('settings-model');
const settingsTokenFieldKey = ValueKey<String>('settings-token-field');

const _modelLabels = {
  'claude-opus-5-5': 'Claude Opus 5.5 · most capable',
  'claude-sonnet-5-5': 'Claude Sonnet 5.5 · faster, lower cost',
  'claude-haiku-5-5': 'Claude Haiku 5.5 · fastest, lowest cost',
};

/// Where the user connects their own Claude key and chooses how runs are made.
///
/// The key is typed into a masked field, sent once to the job service, and the
/// field is cleared at the same moment. This screen never holds it, shows it,
/// or reads it back: the service only returns the last four characters.
class SettingsView extends StatefulWidget {
  const SettingsView({super.key, required this.desk});

  final DeskController desk;

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  final _keyField = TextEditingController();
  final _tokenField = TextEditingController();

  @override
  void dispose() {
    _keyField.dispose();
    _tokenField.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final value = _keyField.text.trim();
    if (value.isEmpty) {
      return;
    }
    // Clear first, so the key is not left in the field whatever happens next.
    _keyField.clear();
    await widget.desk.saveKey(value);
  }

  @override
  Widget build(BuildContext context) {
    final desk = widget.desk;
    final vault = desk.vault;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      children: [
        const SectionLabel('Your model'),
        const SizedBox(height: 8),
        const Text(
          'David can score an engagement with your own Claude API key. The job service encrypts the key on this machine and never shows it again. Without a key, David runs its offline demo.',
          style: TextStyle(color: DavidColors.muted, height: 1.45),
        ),
        const SizedBox(height: 16),
        _StatusCard(desk: desk),
        const SizedBox(height: 16),
        PanelCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Anthropic API key',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
              ),
              const SizedBox(height: 10),
              TextField(
                key: settingsKeyFieldKey,
                controller: _keyField,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                enableIMEPersonalizedLearning: false,
                keyboardType: TextInputType.visiblePassword,
                decoration: const InputDecoration(hintText: 'sk-ant-…'),
                onSubmitted: (_) => _save(),
              ),
              const SizedBox(height: 8),
              const Text(
                'Paste a regular API key. Admin keys are refused. The field clears when you save, so if a save fails, paste the key again.',
                style: TextStyle(color: DavidColors.faint, fontSize: 12.5),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton(
                    key: settingsSaveKey,
                    onPressed: desk.vaultBusy ? null : _save,
                    child: Text(
                      (vault?.configured ?? false)
                          ? 'Replace key'
                          : 'Save and verify',
                    ),
                  ),
                  if (vault?.configured ?? false) ...[
                    OutlinedButton(
                      key: settingsVerifyKey,
                      onPressed: desk.vaultBusy ? null : desk.verifyKey,
                      child: const Text('Verify'),
                    ),
                    OutlinedButton(
                      key: settingsRemoveKey,
                      onPressed: desk.vaultBusy ? null : desk.removeKey,
                      child: const Text('Remove key'),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _RunWithCard(desk: desk),
        const SizedBox(height: 16),
        if (vault != null && vault.cap > 0) ...[
          _UsageCard(vault: vault),
          const SizedBox(height: 16),
        ],
        const _ProtectionCard(),
        const SizedBox(height: 16),
        _AdvancedCard(desk: desk, field: _tokenField),
      ],
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.desk});

  final DeskController desk;

  @override
  Widget build(BuildContext context) {
    final vault = desk.vault;
    final (String title, String body, Color color) = _describe(desk, vault);
    return PanelCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 5, right: 10),
            child: Icon(Icons.circle, size: 10, color: color),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                    color: color,
                  ),
                ),
                if (body.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    body,
                    style: const TextStyle(
                      color: DavidColors.muted,
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (desk.vaultBusy)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
        ],
      ),
    );
  }

  static (String, String, Color) _describe(
    DeskController desk,
    VaultStatus? vault,
  ) {
    final error = desk.vaultError;
    if (vault == null) {
      if (error != null) {
        return ('Job service unreachable', error, DavidColors.negative);
      }
      return ('Checking the job service…', '', DavidColors.muted);
    }
    if (!vault.vaultReady) {
      return (
        'Key vault unavailable',
        vault.vaultReason ?? 'The service cannot store keys right now.',
        DavidColors.negative,
      );
    }
    if (!vault.configured) {
      return (
        'No key saved',
        error ?? 'Runs use the offline demo until you add a key.',
        error == null ? DavidColors.muted : DavidColors.negative,
      );
    }
    if (!vault.readable) {
      return (
        'Saved key cannot be read',
        'The service master key changed. Enter the key again.',
        DavidColors.negative,
      );
    }
    final verified = DateTime.tryParse(vault.verifiedAt ?? '');
    final detail = verified == null
        ? 'Not verified yet.'
        : 'Verified ${formatStamp(verified)}.';
    return (
      'Connected · key ending ••••${vault.last4 ?? ''}',
      error ?? detail,
      error == null ? DavidColors.positive : DavidColors.negative,
    );
  }
}

class _RunWithCard extends StatelessWidget {
  const _RunWithCard({required this.desk});

  final DeskController desk;

  @override
  Widget build(BuildContext context) {
    final vault = desk.vault;
    final usable = vault?.usable ?? false;
    final models = (vault?.models.isNotEmpty ?? false)
        ? vault!.models
        : _modelLabels.keys.toList();
    return PanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Run diligence with',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
          ),
          const SizedBox(height: 10),
          SegmentedButton<bool>(
            key: settingsUseClaudeKey,
            showSelectedIcon: false,
            segments: [
              const ButtonSegment(value: false, label: Text('Offline demo')),
              ButtonSegment(
                value: true,
                enabled: usable,
                label: const Text('Claude, your key'),
              ),
            ],
            selected: {desk.modelActive},
            onSelectionChanged: (choice) => desk.setUseModel(choice.first),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            key: settingsModelKey,
            initialValue: models.contains(desk.model) ? desk.model : null,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Model'),
            dropdownColor: DavidColors.panelRaised,
            items: [
              for (final id in models)
                DropdownMenuItem(
                  value: id,
                  child: Text(_modelLabels[id] ?? id),
                ),
            ],
            onChanged: usable
                ? (value) {
                    if (value != null) {
                      desk.setModel(value);
                    }
                  }
                : null,
          ),
          const SizedBox(height: 8),
          const Text(
            'The model reads the evidence a run retrieved and returns weights. It has no tools, cannot browse, and cannot cite anything the run did not retrieve. David computes the decision.',
            style: TextStyle(color: DavidColors.faint, fontSize: 12.5),
          ),
        ],
      ),
    );
  }
}

class _UsageCard extends StatelessWidget {
  const _UsageCard({required this.vault});

  final VaultStatus vault;

  @override
  Widget build(BuildContext context) {
    return PanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Usage today',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
          ),
          const SizedBox(height: 6),
          Text(
            '${vault.calls} of ${vault.cap} model calls · ${vault.inputTokens} tokens in · ${vault.outputTokens} out',
            style: const TextStyle(color: DavidColors.muted),
          ),
          const SizedBox(height: 4),
          const Text(
            'The cap is set by the job service and stops calls before they are made.',
            style: TextStyle(color: DavidColors.faint, fontSize: 12.5),
          ),
        ],
      ),
    );
  }
}

class _ProtectionCard extends StatelessWidget {
  const _ProtectionCard();

  @override
  Widget build(BuildContext context) {
    const lines = [
      'Sent once to the job service on this machine, then the field is cleared.',
      'Encrypted at rest with AES-256-GCM under a master key the database never sees.',
      'Never returned, logged, or shown again. Only the last four characters are displayed.',
      'Used only to call Anthropic, with a daily call cap and no tools for the model.',
      'This protects a database copy or backup. It does not protect a machine someone else already controls.',
    ];
    return PanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'How your key is protected',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
          ),
          const SizedBox(height: 8),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 6, right: 8),
                    child: Icon(
                      Icons.circle,
                      size: 5,
                      color: DavidColors.brass,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      line,
                      style: const TextStyle(
                        color: DavidColors.muted,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _AdvancedCard extends StatefulWidget {
  const _AdvancedCard({required this.desk, required this.field});

  final DeskController desk;
  final TextEditingController field;

  @override
  State<_AdvancedCard> createState() => _AdvancedCardState();
}

class _AdvancedCardState extends State<_AdvancedCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return PanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Advanced · service token',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  Icon(
                    _open ? Icons.expand_less : Icons.expand_more,
                    color: DavidColors.muted,
                  ),
                ],
              ),
            ),
          ),
          if (_open) ...[
            const SizedBox(height: 8),
            const Text(
              'Only needed if the job service was started with DAVID_API_TOKEN. It is kept in memory for this session and never saved.',
              style: TextStyle(color: DavidColors.faint, fontSize: 12.5),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: settingsTokenFieldKey,
                    controller: widget.field,
                    obscureText: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: const InputDecoration(
                      hintText: 'Service token',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () =>
                      widget.desk.setServiceToken(widget.field.text),
                  child: const Text('Apply'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
