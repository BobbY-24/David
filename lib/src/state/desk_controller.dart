import 'dart:async';

import 'package:flutter/foundation.dart';

import '../agent/provider.dart';
import '../data/engagement_packs.dart';
import '../domain/models.dart';
import '../jobs/job_client.dart';
import '../retrieval/evidence_index.dart';

enum DeskTab { brief, evidence, retrieve, agent, risks, report, control, jobs }

class DeskController extends ChangeNotifier {
  DeskController({EngagementProvider? provider, JobClient? jobClient})
    : provider = provider ?? const DemoProvider(),
      _jobs = jobClient ?? HttpJobClient();

  final EngagementProvider provider;
  final JobClient _jobs;
  Timer? _poll;
  ServiceBoard? board;
  ServiceJob? serviceJob;
  String? serviceError;
  bool enqueueing = false;
  final List<Engagement> cases = EngagementPacks.all;
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
  String evidenceModality = 'all';

  Engagement get current => cases[caseIndex];

  EvidenceIndex indexFor(Engagement engagement) {
    return _indexes.putIfAbsent(
      engagement.id,
      () => EvidenceIndex(engagement.evidence),
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
    evidenceModality = 'all';
    notifyListeners();
  }

  void selectTab(DeskTab next) {
    tab = next;
    notifyListeners();
    if (next == DeskTab.jobs) {
      refreshBoard();
    }
  }

  Future<void> refreshBoard() async {
    final next = await _jobs.board();
    board = next;
    notifyListeners();
  }

  Future<void> enqueueJob(CatalogItem item) async {
    if (enqueueing) {
      return;
    }
    enqueueing = true;
    serviceError = null;
    notifyListeners();
    try {
      serviceJob = await _jobs.enqueue(
        kind: item.kind,
        spec: item.spec,
        idempotencyKey:
            '${item.kind}-${item.title}-${DateTime.now().microsecondsSinceEpoch}',
      );
      _ensurePoll();
    } on JobClientException catch (error) {
      serviceError = error.message;
    } finally {
      enqueueing = false;
      notifyListeners();
    }
  }

  Future<void> refreshJob() async {
    final currentJob = serviceJob;
    if (currentJob == null) {
      return;
    }
    try {
      serviceJob = await _jobs.fetch(currentJob.id);
      if (serviceJob?.status == 'succeeded' || serviceJob?.status == 'dead') {
        await refreshBoard();
      }
      _ensurePoll();
    } on JobClientException catch (error) {
      serviceError = error.message;
      _poll?.cancel();
      _poll = null;
      notifyListeners();
    }
  }

  void _ensurePoll() {
    final status = serviceJob?.status;
    final active = status == 'queued' || status == 'running';
    if (!active) {
      _poll?.cancel();
      _poll = null;
      return;
    }
    _poll ??= Timer.periodic(const Duration(seconds: 1), (_) {
      refreshJob();
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
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

  void setEvidenceModality(String modality) {
    evidenceModality = modality;
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

  Future<void> runDiligence() async {
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
      run = provider.run(current);
      tab = DeskTab.agent;
    } catch (caught) {
      error = 'The investigation policy stopped: $caught';
    } finally {
      running = false;
      notifyListeners();
    }
  }
}
