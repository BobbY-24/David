import 'dart:convert';

import 'package:http/http.dart' as http;

class CatalogItem {
  const CatalogItem({
    required this.kind,
    required this.title,
    required this.blurb,
    required this.spec,
  });

  final String kind;
  final String title;
  final String blurb;
  final Map<String, Object?> spec;

  factory CatalogItem.fromJson(Map<String, Object?> json) {
    final spec = json['spec'];
    return CatalogItem(
      kind: json['kind'] as String? ?? '',
      title: json['title'] as String? ?? '',
      blurb: json['blurb'] as String? ?? '',
      spec: spec is Map<String, Object?>
          ? spec
          : Map<String, Object?>.from(spec as Map? ?? const {}),
    );
  }
}

class ServiceBoard {
  const ServiceBoard({
    required this.ok,
    required this.items,
    required this.depth,
    required this.succeeded,
    required this.dead,
    required this.throughput,
    this.waitP95,
    this.e2eP95,
    this.e2eP99,
    this.error,
  });

  final bool ok;
  final List<CatalogItem> items;
  final int depth;
  final int succeeded;
  final int dead;
  final double throughput;
  final double? waitP95;
  final double? e2eP95;
  final double? e2eP99;
  final String? error;
}

class ServiceJob {
  const ServiceJob({
    required this.id,
    required this.status,
    required this.kind,
    required this.attempts,
    this.headline,
    this.detail,
    this.error,
    this.queueWaitMs,
    this.e2eMs,
  });

  final String id;
  final String status;
  final String kind;
  final int attempts;
  final String? headline;
  final String? detail;
  final String? error;
  final double? queueWaitMs;
  final double? e2eMs;

  factory ServiceJob.fromJson(Map<String, Object?> json) {
    return ServiceJob(
      id: json['id'] as String? ?? '',
      status: json['status'] as String? ?? '',
      kind: json['kind'] as String? ?? '',
      attempts: (json['attempts'] as num?)?.toInt() ?? 0,
      headline: json['headline'] as String?,
      detail: json['detail'] as String?,
      error: json['error'] as String?,
      queueWaitMs: (json['queue_wait_ms'] as num?)?.toDouble(),
      e2eMs: (json['e2e_ms'] as num?)?.toDouble(),
    );
  }
}

class JobClientException implements Exception {
  JobClientException(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract class JobClient {
  Future<ServiceBoard> board();

  Future<ServiceJob> enqueue({
    required String kind,
    required Map<String, Object?> spec,
    required String idempotencyKey,
  });

  Future<ServiceJob> fetch(String id);
}

class HttpJobClient implements JobClient {
  HttpJobClient({http.Client? httpClient, String? baseUrl})
    : _http = httpClient ?? http.Client(),
      baseUrl =
          baseUrl ??
          const String.fromEnvironment(
            'JOBS_API',
            defaultValue: 'http://127.0.0.1:43124',
          );

  final http.Client _http;
  final String baseUrl;

  @override
  Future<ServiceBoard> board() async {
    try {
      final health = await _get('/v1/health');
      if (health['ok'] != true) {
        return _down('The job service is up but the database check failed.');
      }
      final catalog = await _get('/v1/catalog');
      final metrics = await _get('/v1/metrics');
      final rawItems = catalog['items'];
      final items = <CatalogItem>[];
      if (rawItems is List) {
        for (final item in rawItems) {
          if (item is Map) {
            items.add(CatalogItem.fromJson(Map<String, Object?>.from(item)));
          }
        }
      }
      final wait = metrics['queue_wait_ms'];
      final e2e = metrics['e2e_ms'];
      return ServiceBoard(
        ok: true,
        items: items,
        depth: (metrics['depth'] as num?)?.toInt() ?? 0,
        succeeded: (metrics['succeeded'] as num?)?.toInt() ?? 0,
        dead: (metrics['dead'] as num?)?.toInt() ?? 0,
        throughput: (metrics['throughput_per_s'] as num?)?.toDouble() ?? 0,
        waitP95: wait is Map ? (wait['p95'] as num?)?.toDouble() : null,
        e2eP95: e2e is Map ? (e2e['p95'] as num?)?.toDouble() : null,
        e2eP99: e2e is Map ? (e2e['p99'] as num?)?.toDouble() : null,
      );
    } on JobClientException catch (error) {
      return _down(error.message);
    }
  }

  @override
  Future<ServiceJob> enqueue({
    required String kind,
    required Map<String, Object?> spec,
    required String idempotencyKey,
  }) async {
    final response = await _send(
      () => _http.post(
        Uri.parse('$baseUrl/v1/jobs'),
        headers: {
          'content-type': 'application/json',
          'Idempotency-Key': idempotencyKey,
        },
        body: jsonEncode({'kind': kind, 'spec': spec}),
      ),
    );
    return ServiceJob.fromJson(_decode(response));
  }

  @override
  Future<ServiceJob> fetch(String id) async {
    final body = await _get('/v1/jobs/$id');
    return ServiceJob.fromJson(body);
  }

  ServiceBoard _down(String message) {
    return ServiceBoard(
      ok: false,
      items: const [],
      depth: 0,
      succeeded: 0,
      dead: 0,
      throughput: 0,
      error: message,
    );
  }

  Future<Map<String, Object?>> _get(String path) async {
    final response = await _send(() => _http.get(Uri.parse('$baseUrl$path')));
    return _decode(response);
  }

  Future<http.Response> _send(Future<http.Response> Function() send) async {
    try {
      final response = await send().timeout(const Duration(seconds: 4));
      if (response.statusCode >= 400) {
        throw JobClientException(_errorMessage(response));
      }
      return response;
    } on JobClientException {
      rethrow;
    } catch (error) {
      throw JobClientException('The job service on $baseUrl is not answering.');
    }
  }

  Map<String, Object?> _decode(http.Response response) {
    final decoded = jsonDecode(response.body);
    if (decoded is Map) {
      return Map<String, Object?>.from(decoded);
    }
    throw JobClientException('The job service returned an unexpected body.');
  }

  String _errorMessage(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map && decoded['detail'] is String) {
        return decoded['detail'] as String;
      }
    } catch (_) {
      // Fall through to the status line.
    }
    return 'The job service returned ${response.statusCode}.';
  }
}
