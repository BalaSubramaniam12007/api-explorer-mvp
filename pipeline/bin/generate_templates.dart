import 'dart:io';

/// Runs template generation using parser + storage modules.
import 'package:api_explorer_pipeline/generator.dart';

/// Entrypoint for generation run.
Future<void> main(List<String> args) async {
  final all = args.contains('--all');
  final root = Directory.current;
  final registry = await readJson(File('${root.path}/registry/registry.json'));
  final targets = await targetApiIds(
    all: all,
    registry: registry,
    updatesFile: File('${root.path}/registry/updates.json'),
  );
  final version = DateTime.now().toUtc().toIso8601String().split('T').first;

  for (final apiId in targets) {
    final source = registry[apiId];
    if (source is! Map) continue;
    await generateForApi(
      root: root,
      apiId: apiId,
      source: Map<String, dynamic>.from(source),
      version: version,
    );
  }

  await refreshGlobalIndex(root, registry);
  await writeCurrent(root);
}
