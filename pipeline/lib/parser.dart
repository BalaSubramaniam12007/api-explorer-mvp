/// Fetches OpenAPI specs and maps endpoints to APIDash template shape.
library;

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:openapi_spec/openapi_spec.dart';
import 'package:yaml/yaml.dart';

/// Fetches and parses one OpenAPI document. Returns null on failure.
Future<OpenApi?> fetchSpec(String url) async {
  try {
    final response = await http.get(Uri.parse(url));
    if (response.statusCode < 200 || response.statusCode >= 300) return null;
    return _parseSpec(response.body);
  } catch (_) {
    return null;
  }
}

/// Parses raw JSON or YAML into an [OpenApi] model.
OpenApi? _parseSpec(String raw) {
  try {
    Map<String, dynamic> map;
    try {
      map = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      map = jsonDecode(jsonEncode(loadYaml(raw))) as Map<String, dynamic>;
    }
    return OpenApi.fromJson(map);
  } catch (_) {
    return null;
  }
}

/// Returns base URL from the first server entry.
String _baseUrl(OpenApi spec) {
  final url = spec.servers?.firstOrNull?.url ?? '';
  return url.endsWith('/') ? url.substring(0, url.length - 1) : url;
}

/// Builds a minimal auth model from the first declared security scheme.
Map<String, dynamic> _authModel(OpenApi spec) {
  final base = <String, dynamic>{
    'type': 'none',
    'apikey': null,
    'bearer': null,
    'basic': null,
    'jwt': null,
    'digest': null,
    'oauth1': null,
    'oauth2': null,
  };
  final schemes = spec.components?.securitySchemes;
  if (schemes == null || schemes.isEmpty) return base;

  // Safely detect auth type from first scheme
  try {
    final first = schemes.values.first;
    final schemeType = first.toJson()['type']?.toString() ?? '';
    if (schemeType.contains('apiKey')) base['type'] = 'apikey';
    if (schemeType.contains('http')) base['type'] = 'bearer';
  } catch (_) {
    // Silently ignore parsing errors
  }
  return base;
}

/// Creates a deterministic ID from API ID, method, and path.
String _endpointId(String apiId, String method, String path) =>
    '$apiId-$method-$path'
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');

/// Safely extracts operation ID from an operation.
String? _getOperationId(Operation operation) {
  try {
    return operation.toJson()['operationId']?.toString();
  } catch (_) {
    return null;
  }
}

/// Safely extracts parameter location.
String _parameterLocation(Parameter p) {
  try {
    return p.toJson()['in']?.toString() ?? '';
  } catch (_) {
    return '';
  }
}

/// Builds one APIDash-shaped template from one [Operation].
Map<String, dynamic> _buildTemplate({
  required String apiId,
  required String base,
  required String path,
  required String method,
  required Operation operation,
  required Map<String, dynamic> auth,
}) {
  final params = <Map<String, dynamic>>[];
  final headers = <Map<String, dynamic>>[];

  for (final p in operation.parameters ?? []) {
    final name = p.name ?? 'value';
    final value = '{{${name.toUpperCase()}}}';
    final paramIn = _parameterLocation(p);

    if (paramIn.contains('query') || paramIn.contains('path')) {
      params.add({'name': name, 'value': value});
    } else if (paramIn.contains('header')) {
      headers.add({'name': name, 'value': value});
    }
  }

  final content = operation.requestBody?.content;
  var bodyType = 'json';
  String? body;
  if (content != null) {
    if (content.containsKey('application/json')) body = '{}';
    if (content.containsKey('application/x-www-form-urlencoded')) bodyType = 'form';
    if (content.containsKey('multipart/form-data')) bodyType = 'multipart';
  }

  return {
    'id': _endpointId(apiId, method, path),
    'apiType': 'rest',
    'name': operation.summary ??
        _getOperationId(operation) ??
        '${method.toUpperCase()} $path',
    'description': operation.description ?? '',
    'httpRequestModel': {
      'method': method,
      'url': '$base$path',
      'headers': headers,
      'params': params,
      'authModel': auth,
      'isHeaderEnabledList': List.generate(headers.length, (_) => true),
      'isParamEnabledList': List.generate(params.length, (_) => true),
      'bodyContentType': bodyType,
      'body': body,
      'query': null,
      'formData': <Map<String, dynamic>>[],
    },
    'responseStatus': null,
    'message': null,
    'httpResponseModel': null,
    'preRequestScript': null,
    'postRequestScript': null,
    'aiRequestModel': null,
  };
}

/// Converts one [OpenApi] model into an APIDash request template list.
List<Map<String, dynamic>> extractTemplates({
  required String apiId,
  required OpenApi spec,
}) {
  final base = _baseUrl(spec);
  final auth = _authModel(spec);
  final templates = <Map<String, dynamic>>[];

  final paths = spec.paths;
  if (paths == null) return templates;

  for (final pathEntry in paths.entries) {
    final path = pathEntry.key;
    final item = pathEntry.value;

    for (final (method, op) in [
      ('get', item.get),
      ('post', item.post),
      ('put', item.put),
      ('patch', item.patch),
      ('delete', item.delete),
      ('head', item.head),
      ('options', item.options),
    ]) {
      if (op == null) continue;
      templates.add(_buildTemplate(
        apiId: apiId,
        base: base,
        path: path,
        method: method,
        operation: op,
        auth: auth,
      ));
    }
  }
  return templates;
}
