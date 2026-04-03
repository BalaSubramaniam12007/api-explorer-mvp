/// Generates versioned template files and index artifacts.
library;

import 'dart:convert';
import 'dart:io';
import 'parser.dart';

/// Reads JSON map from file or returns empty map when missing.
Future<Map<String, dynamic>> readJson(File file) async {
  if (!await file.exists()) return <String, dynamic>{};
  final text = await file.readAsString();
  if (text.trim().isEmpty) return <String, dynamic>{};
  final data = jsonDecode(text);
  return data is Map<String, dynamic> ? data : <String, dynamic>{};
}

/// Writes JSON with indentation and ensures parent folders exist.
Future<void> writeJson(File file, Object data) async {
  await file.parent.create(recursive: true);
  final encoder = const JsonEncoder.withIndent('  ');
  await file.writeAsString('${encoder.convert(data)}\n');
}

/// Resolves target API IDs using updates file unless all flag is true.
Future<List<String>> targetApiIds({
  required bool all,
  required Map<String, dynamic> registry,
  required File updatesFile,
}) async {
  if (all) return registry.keys.toList();
  final updates = await readJson(updatesFile);
  final updated = updates['updated_ids'];
  if (updated is List && updated.isNotEmpty)
    return updated.map((e) => e.toString()).toList();
  return registry.keys.toList();
}

/// Generates templates and per-API index for one API entry.
Future<void> generateForApi({
  required Directory root,
  required String apiId,
  required Map<String, dynamic> source,
  required String version,
}) async {
  final openapiUrl = source['openapi_url']?.toString() ?? '';
  if (openapiUrl.isEmpty) return;

  final spec = await fetchSpec(openapiUrl);
  if (spec.isEmpty) return;

  final templates = extractTemplates(apiId: apiId, spec: spec);
  final apiRoot = Directory('${root.path}/api_templates/apis/$apiId');
  await apiRoot.create(recursive: true);
  await writeJson(File('${apiRoot.path}/$version/templates.json'), templates);

  final indexFile = File('${apiRoot.path}/index.json');
  final existing = await readJson(indexFile);
  final versions = <String>{
    ...((existing['versions'] as List?)?.map((e) => e.toString()) ?? const []),
    version,
  }.toList()
    ..sort();

  await writeJson(indexFile, {
    'id': apiId,
    'name': source['name']?.toString() ?? apiId,
    'category': source['category']?.toString() ?? 'uncategorized',
    'latest_version': version,
    'versions': versions,
  });
}

/// Regenerates global index from all available per-API indexes.
Future<void> refreshGlobalIndex(
    Directory root, Map<String, dynamic> registry) async {
  final apis = <Map<String, dynamic>>[];
  final categories = <String>{};

  for (final entry in registry.entries) {
    final apiId = entry.key;
    final source = entry.value is Map
        ? Map<String, dynamic>.from(entry.value as Map)
        : <String, dynamic>{};
    final indexFile = File('${root.path}/api_templates/apis/$apiId/index.json');
    if (!await indexFile.exists()) continue;
    final apiIndex = await readJson(indexFile);
    apis.add({
      'id': apiId,
      'name': source['name']?.toString() ?? apiId,
      'category': source['category']?.toString() ?? 'uncategorized',
      'latest_version': apiIndex['latest_version']?.toString() ?? '',
    });
    categories.add(source['category']?.toString() ?? 'uncategorized');
  }

  apis.sort((a, b) => (a['id'] as String).compareTo(b['id'] as String));
  final sortedCategories = categories.toList()..sort();
  await writeJson(File('${root.path}/api_templates/global_index.json'), {
    'apis': apis,
    'categories': sortedCategories,
  });
}

/// Writes current pointer metadata for client fetch flow.
Future<void> writeCurrent(Directory root) async {
  final sha = Platform.environment['GITHUB_SHA'] ?? 'local';
  await writeJson(File('${root.path}/api_templates/current.json'), {
    'sha': sha,
    'updatedAt': DateTime.now().toUtc().toIso8601String(),
  });
}
