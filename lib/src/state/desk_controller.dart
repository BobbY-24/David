import 'package:flutter/foundation.dart';

import '../agent/investigation_agent.dart';
import '../data/case_packs.dart';
import '../domain/models.dart';
import '../retrieval/evidence_index.dart';

enum DeskTab {
  brief,
  observations,
  retrieve,
  agent,
  explanations,
  report,
  control,
}

class DeskController extends ChangeNotifier {
  DeskController({InvestigationAgent? agent})
    : _agent = agent ?? const InvestigationAgent();

  final InvestigationAgent _agent;
  final List<InvestigationCase> cases = CasePacks.all;
  final Map<String, EvidenceIndex> _indexes = {};

  int caseIndex = 0;
  DeskTab tab = DeskTab.brief;
  AgentRun? run;
  bool running = false;
  String? error;
  String? selectedEvidenceId;
  String queryText = '';
  String? modalityFilter;
  SourceKind? kindFilter;
  List<RetrievalHit> manualHits = const [];
  bool manualSearched = false;
  String observationModality = 'all';

  InvestigationCase get current => cases[caseIndex];

  EvidenceIndex indexFor(InvestigationCase caseFile) {
    return _indexes.putIfAbsent(
      caseFile.id,
      () => EvidenceIndex(caseFile.evidence),
    );
  }

  EvidenceUnit? get selected {
    final id = selectedEvidenceId;
    if (id == null) {
      return null;
    }
    for (final unit in current.evidence) {
      if (unit.id == id) {
        return unit;
      }
    }
    return null;
  }

  void selectCase(int index) {
    if (index < 0 || index >= cases.length || index == caseIndex) {
      return;
    }
    caseIndex = index;
    tab = DeskTab.brief;
    run = null;
    running = false;
    error = null;
    selectedEvidenceId = null;
    queryText = '';
    modalityFilter = null;
    kindFilter = null;
    manualHits = const [];
    manualSearched = false;
    observationModality = 'all';
    notifyListeners();
  }

  void selectTab(DeskTab next) {
    tab = next;
    notifyListeners();
  }

  void selectEvidence(String? id) {
    selectedEvidenceId = id;
    notifyListeners();
  }

  void setQueryText(String value) {
    queryText = value;
    notifyListeners();
  }

  void setModalityFilter(String? modality) {
    modalityFilter = modality;
    notifyListeners();
  }

  void setKindFilter(SourceKind? kind) {
    kindFilter = kind;
    notifyListeners();
  }

  void setObservationModality(String modality) {
    observationModality = modality;
    notifyListeners();
  }

  void searchManual() {
    manualHits = indexFor(current).search(
      RetrievalQuery(
        text: queryText,
        modality: modalityFilter,
        sourceKind: kindFilter,
        limit: 12,
      ),
    );
    manualSearched = true;
    notifyListeners();
  }

  void useExample(String query) {
    queryText = query;
    searchManual();
  }

  Future<void> runInvestigation() async {
    if (running) {
      return;
    }
    final caseId = current.id;
    running = true;
    error = null;
    notifyListeners();
    await Future<void>.delayed(const Duration(milliseconds: 320));
    if (caseId != current.id) {
      running = false;
      notifyListeners();
      return;
    }
    try {
      run = _agent.investigate(current);
      tab = DeskTab.agent;
    } catch (caught) {
      error = 'The investigation policy stopped: $caught';
    } finally {
      running = false;
      notifyListeners();
    }
  }
}
