/// Generates versioned template files and index artifacts.
library;

import 'dart:convert';
import 'dart:io';
import 'parser.dart';

/// Reads a JSON map from [file], returning an empty map when missing.
Future<Map<String, dynamic>> readJson(File file) async {
  if (!await file.exists()) return {};
  final text = await file.readAsString();
  if (text.trim().isEmpty) return {};
  final data = jsonDecode(text);
  return data is Map<String, dynamic> ? data : {};
}

/// Writes [data] as indented JSON to [file], creating parent dirs as needed.
Future<void> writeJson(File file, Object data) async {
  await file.parent.create(recursive: true);
  await file.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(data)}\n',
  );
}

/// Returns API IDs to process: from [updatesFile] unless [all] is true.
Future<List<String>> targetApiIds({
  required bool all,
  required Map<String, dynamic> registry,
  required File updatesFile,
}) async {
  if (all) return registry.keys.toList();
  final updates = await readJson(updatesFile);
  final updated = updates['updated_ids'];
  return updated is List
      ? updated.map((e) => e.toString()).toList()
      : registry.keys.toList();
}

/// Generates versioned templates and per-API index for one API entry.
Future<void> generateForApi({
  required Directory root,
  required String apiId,
  required Map<String, dynamic> source,
  required String version,
}) async {
  final url = source['openapi_url']?.toString() ?? '';
  if (url.isEmpty) return;

  final spec = await fetchSpec(url);
  if (spec == null) return;

  final templates = extractTemplates(apiId: apiId, spec: spec);
  final apiRoot = Directory('${root.path}/api_templates/apis/$apiId');
  await writeJson(File('${apiRoot.path}/$version/templates.json'), templates);

  final indexFile = File('${apiRoot.path}/index.json');
  final existing = await readJson(indexFile);
  final versions = <String>{
    ...((existing['versions'] as List?)?.map((e) => e.toString()) ?? []),
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

/// Regenerates global_index.json from all per-API index files.
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
    final index = await readJson(indexFile);
    final category = source['category']?.toString() ?? 'uncategorized';
    apis.add({
      'id': apiId,
      'name': source['name']?.toString() ?? apiId,
      'category': category,
      'latest_version': index['latest_version']?.toString() ?? '',
    });
    categories.add(category);
  }

  apis.sort((a, b) => (a['id'] as String).compareTo(b['id'] as String));

  await writeJson(File('${root.path}/api_templates/global_index.json'), {
    'apis': apis,
    'categories': categories.toList()..sort(),
  });
}
