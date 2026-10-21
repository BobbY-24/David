import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// A failure from the key vault or the model route. [message] is safe to show:
/// it never contains the key.
class ModelServiceException implements Exception {
  const ModelServiceException(this.code, this.message, {this.status});

  final String code;
  final String message;
  final int? status;

  @override
  String toString() => message;
}

/// One HTTP path to the job service. Every desk client to the service goes
/// through it, so the optional service token is attached in one place.
class ServiceTransport {
  ServiceTransport({http.Client? httpClient, required this.baseUrl})
    : _http = httpClient ?? http.Client();

  final http.Client _http;
  final String baseUrl;
  String? _token;

  void setToken(String? token) {
    _token = (token == null || token.trim().isEmpty) ? null : token.trim();
  }

  Future<Map<String, Object?>> send(
    String method,
    String path, {
    Object? body,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final request = http.Request(method, Uri.parse('$baseUrl$path'))
      ..headers['Content-Type'] = 'application/json';
    final token = _token;
    if (token != null) {
      request.headers['X-David-Token'] = token;
    }
    if (body != null) {
      request.body = jsonEncode(body);
    }
    final http.Response response;
    try {
      response = await http.Response.fromStream(
        await _http.send(request).timeout(timeout),
      );
    } on TimeoutException {
      throw const ModelServiceException(
        'timeout',
        'The job service took too long to answer.',
      );
    } on Exception {
      throw ModelServiceException(
        'service_unreachable',
        'The job service is not reachable at $baseUrl. Start it to use your own key.',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _error(response);
    }
    try {
      return _map(jsonDecode(response.body));
    } on FormatException {
      throw ModelServiceException(
        'bad_response',
        'The job service sent an answer David could not read.',
        status: response.statusCode,
      );
    }
  }

  ModelServiceException _error(http.Response response) {
    var code = 'error';
    var message =
        'The job service answered with status ${response.statusCode}.';
    try {
      final detail = _map(jsonDecode(response.body))['detail'];
      if (detail is Map<String, Object?>) {
        code = detail['code'] as String? ?? code;
        message = detail['message'] as String? ?? message;
      } else if (detail is String) {
        message = detail;
      } else if (detail is List<Object?>) {
        code = 'invalid_request';
        message = 'The service could not accept that request.';
      }
    } on FormatException {
      // Keep the generic message.
    }
    return ModelServiceException(code, message, status: response.statusCode);
  }
}

Map<String, Object?> _map(Object? value) {
  return value is Map<String, Object?> ? value : const {};
}
