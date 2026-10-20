import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../domain/models.dart';
import 'rails.dart';

class Principal {
  const Principal({required this.id, required this.caseGrants});

  final String id;
  final Set<String> caseGrants;

  static Principal deskOperator(String caseId) {
    return Principal(id: 'desk-operator', caseGrants: {caseId});
  }

  bool grants(String caseId) => caseGrants.contains(caseId);
}

class ToolCallResult<T> {
  const ToolCallResult({
    required this.allowed,
    required this.detail,
    this.value,
  });

  final bool allowed;
  final String detail;
  final T? value;
}

/// Session gateway in front of every tool.
///
/// Allowlist, case grant, and a per-run call budget are enforced here, outside
/// the scorer. Denied calls are still audited. The hash chain covers the
/// redacted query so the log does not need the raw text to be checkable.
class ToolGateway {
  ToolGateway({required this.principal, this.budget = 32});

  static const allowlist = {'search'};

  final Principal principal;
  final int budget;
  int used = 0;
  final List<AuditEvent> audit = [];
  final List<String> denied = [];
  String _prev = '0' * 64;

  ToolCallResult<T> call<T>({
    required String tool,
    required String caseId,
    required String query,
    required T Function() body,
  }) {
    final redacted = redactForLog(query);
    final String decision;
    final String detail;
    T? value;
    if (!allowlist.contains(tool)) {
      decision = 'deny';
      detail =
          'Tool "$tool" is outside the allowlist. The only tool is search.';
      denied.add(tool);
    } else if (!principal.grants(caseId)) {
      decision = 'deny';
      detail = 'Principal ${principal.id} has no grant for $caseId.';
      denied.add('scope:$caseId');
    } else if (used >= budget) {
      decision = 'deny';
      detail = 'Session tool budget of $budget calls is spent.';
      denied.add('budget');
    } else {
      used += 1;
      decision = 'allow';
      detail = 'Read allowed inside the case grant.';
      value = body();
    }
    final hash = auditHash(_prev, '$decision|$tool|$caseId|$redacted');
    audit.add(
      AuditEvent(
        seq: audit.length,
        tool: tool,
        decision: decision,
        caseId: caseId,
        redactedQuery: redacted,
        prevHash: _prev,
        hash: hash,
      ),
    );
    _prev = hash;
    return ToolCallResult(
      allowed: decision == 'allow',
      detail: detail,
      value: value,
    );
  }
}

String auditHash(String prev, String body) {
  return sha256.convert(utf8.encode('$prev|$body')).toString();
}
