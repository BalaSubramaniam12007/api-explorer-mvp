/// Parses OpenAPI documents and maps endpoints to API Dash template shape.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:yaml/yaml.dart';

const httpMethods = {
  'get',
  'post',
  'put',
  'patch',
  'delete',
  'head',
  'options'
};

/// Loads JSON or YAML OpenAPI text into a map.
Map<String, dynamic> parseOpenApi(String raw) {
  try {
    final jsonMap = jsonDecode(raw);
    return jsonMap is Map<String, dynamic> ? jsonMap : <String, dynamic>{};
  } catch (_) {
    final yamlDoc = loadYaml(raw);
    final normalized = jsonDecode(jsonEncode(yamlDoc));
    return normalized is Map<String, dynamic>
        ? normalized
        : <String, dynamic>{};
  }
}

/// Fetches one OpenAPI document and returns parsed map data.
Future<Map<String, dynamic>> fetchSpec(String url) async {
  final response = await http.get(Uri.parse(url));
  if (response.statusCode < 200 || response.statusCode >= 300)
    return <String, dynamic>{};
  return parseOpenApi(response.body);
}

/// Returns base URL from OpenAPI 3 servers or OpenAPI 2 host fields.
String getBaseUrl(Map<String, dynamic> spec) {
  final servers = spec['servers'];
  if (servers is List && servers.isNotEmpty && servers.first is Map) {
    return ((servers.first as Map)['url']?.toString() ?? '')
        .replaceAll(RegExp(r'/$'), '');
  }
  final schemes = spec['schemes'];
  final scheme = schemes is List && schemes.isNotEmpty
      ? schemes.first.toString()
      : 'https';
  final host = spec['host']?.toString() ?? '';
  final basePath = spec['basePath']?.toString() ?? '';
  return '$scheme://$host$basePath'.replaceAll(RegExp(r'/$'), '');
}

/// Creates a minimal auth model from first security scheme.
Map<String, dynamic> authModel(Map<String, dynamic> spec) {
  final model = {
    'type': 'none',
    'apikey': null,
    'bearer': null,
    'basic': null,
    'jwt': null,
    'digest': null,
    'oauth1': null,
    'oauth2': null,
  };
  final components = spec['components'];
  if (components is! Map) return model;
  final schemes = components['securitySchemes'];
  if (schemes is! Map || schemes.isEmpty) return model;
  final first = schemes.values.first;
  if (first is! Map) return model;
  final type = first['type']?.toString() ?? '';
  final scheme = first['scheme']?.toString() ?? '';
  if (type == 'apiKey') model['type'] = 'apikey';
  if (type == 'http' && scheme == 'bearer') model['type'] = 'bearer';
  return model;
}

/// Creates deterministic endpoint id from API ID, method, and path.
String endpointId(String apiId, String method, String path) {
  final raw = '$apiId-$method-$path'.toLowerCase();
  return raw
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');
}

/// Builds one API Dash-shaped template from one endpoint operation.
Map<String, dynamic> buildTemplate({
  required String apiId,
  required String base,
  required String path,
  required String method,
  required Map<String, dynamic> operation,
  required Map<String, dynamic> auth,
}) {
  final parameters = (operation['parameters'] is List)
      ? List<Map<String, dynamic>>.from(operation['parameters'])
      : <Map<String, dynamic>>[];
  final params = <Map<String, dynamic>>[];
  final headers = <Map<String, dynamic>>[];

  for (final p in parameters) {
    final name = p['name']?.toString() ?? 'value';
    final location = p['in']?.toString() ?? '';
    final value = '{{${name.toUpperCase()}}}';
    if (location == 'query' || location == 'path')
      params.add({'name': name, 'value': value});
    if (location == 'header') headers.add({'name': name, 'value': value});
  }

  final requestBody = operation['requestBody'];
  final content = requestBody is Map ? requestBody['content'] : null;
  var bodyType = 'json';
  String? body;
  if (content is Map) {
    if (content.containsKey('application/json')) body = '{}';
    if (content.containsKey('application/x-www-form-urlencoded'))
      bodyType = 'form';
    if (content.containsKey('multipart/form-data')) bodyType = 'multipart';
  }

  return {
    'id': endpointId(apiId, method, path),
    'apiType': 'rest',
    'name': operation['summary']?.toString() ??
        operation['operationId']?.toString() ??
        '${method.toUpperCase()} $path',
    'description': operation['description']?.toString() ?? '',
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

/// Converts one OpenAPI spec map into API Dash request template list.
List<Map<String, dynamic>> extractTemplates({
  required String apiId,
  required Map<String, dynamic> spec,
}) {
  final base = getBaseUrl(spec);
  final auth = authModel(spec);
  final templates = <Map<String, dynamic>>[];
  final paths = spec['paths'];
  if (paths is! Map) return templates;

  for (final entry in paths.entries) {
    final path = entry.key.toString();
    final operations = entry.value;
    if (operations is! Map) continue;
    for (final op in operations.entries) {
      final method = op.key.toString().toLowerCase();
      if (!httpMethods.contains(method) || op.value is! Map) continue;
      templates.add(buildTemplate(
        apiId: apiId,
        base: base,
        path: path,
        method: method,
        operation: Map<String, dynamic>.from(op.value as Map),
        auth: auth,
      ));
    }
  }
  return templates;
}
