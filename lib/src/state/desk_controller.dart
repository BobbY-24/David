import 'dart:async';

import 'package:flutter/foundation.dart';

import '../agent/model_provider.dart';
import '../agent/provider.dart';
import '../data/engagement_packs.dart';
import '../domain/models.dart';
import '../jobs/job_client.dart';
import '../jobs/model_service.dart';
import '../retrieval/evidence_index.dart';

enum DeskTab {
  brief,
  evidence,
  retrieve,
  agent,
  risks,
  report,
  control,
  jobs,
  settings,
}

class DeskController extends ChangeNotifier {
  DeskController({
    EngagementProvider? provider,
    JobClient? jobClient,
    ModelService? modelService,
  }) : demoProvider = provider ?? const DemoProvider(),
       _jobs = jobClient ?? HttpJobClient(),
       _models = modelService ?? HttpModelService();

  /// The offline provider. Always available, needs no key.
  final EngagementProvider demoProvider;
  final JobClient _jobs;
  final ModelService _models;

  /// What the service says about the saved key. Never the key itself.
  VaultStatus? vault;
  bool vaultBusy = false;
  String? vaultError;

  /// Run with the user's Claude key instead of the offline demo.
  bool useModel = false;
  String model = ModelProvider.defaultModel;

  bool get modelActive => useModel && (vault?.usable ?? false);

  EngagementProvider get provider =>
      modelActive ? ModelProvider(judge: _models, model: model) : demoProvider;
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
    if (next == DeskTab.settings) {
      refreshVault();
    }
  }

  Future<void> refreshVault() async {
    vaultBusy = true;
    notifyListeners();
    try {
      _adopt(await _models.status());
    } on ModelServiceException catch (caught) {
      vault = null;
      vaultError = caught.message;
      useModel = false;
    } finally {
      vaultBusy = false;
      notifyListeners();
    }
  }

  /// Sends the key to the service. The key is not stored here.
  Future<bool> saveKey(String key) async {
    vaultBusy = true;
    vaultError = null;
    notifyListeners();
    try {
      _adopt(await _models.saveKey(key));
      useModel = vault?.usable ?? false;
      return true;
    } on ModelServiceException catch (caught) {
      vaultError = caught.message;
      return false;
    } finally {
      vaultBusy = false;
      notifyListeners();
    }
  }

  Future<void> verifyKey() async {
    vaultBusy = true;
    vaultError = null;
    notifyListeners();
    try {
      _adopt(await _models.verifyKey());
    } on ModelServiceException catch (caught) {
      vaultError = caught.message;
    } finally {
      vaultBusy = false;
      notifyListeners();
    }
  }

  Future<void> removeKey() async {
    vaultBusy = true;
    vaultError = null;
    notifyListeners();
    try {
      _adopt(await _models.removeKey());
      useModel = false;
    } on ModelServiceException catch (caught) {
      vaultError = caught.message;
    } finally {
      vaultBusy = false;
      notifyListeners();
    }
  }

  void setUseModel(bool value) {
    useModel = value && (vault?.usable ?? false);
    notifyListeners();
  }

  void setModel(String value) {
    model = value;
    notifyListeners();
  }

  Future<void> setServiceToken(String token) async {
    _models.setToken(token);
    await refreshVault();
  }

  void _adopt(VaultStatus status) {
    vault = status;
    vaultError = null;
    if (!status.usable) {
      useModel = false;
    }
    if (status.models.isNotEmpty && !status.models.contains(model)) {
      model = status.defaultModel.isNotEmpty
          ? status.defaultModel
          : status.models.first;
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
    final usedModel = modelActive;
    try {
      final result = await provider.runAsync(current);
      if (caseId != current.id) {
        return;
      }
      run = result;
      tab = DeskTab.agent;
    } on ModelServiceException catch (caught) {
      error = caught.message;
    } catch (caught) {
      error = 'The investigation policy stopped: $caught';
    } finally {
      running = false;
      notifyListeners();
    }
    if (usedModel) {
      unawaited(refreshVault());
    }
  }
}
