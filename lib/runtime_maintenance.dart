import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

/// A successful face is registered once per family and content. Failures retry.
class ImportedFontCache {
  final Future<void> Function(String, String) register;
  final _loaded = <String>{};
  final _inFlight = <String, Future<void>>{};
  ImportedFontCache(this.register);
  Future<void> load(String family, String encoded) async {
    final key = '$family:${sha256.convert(utf8.encode(encoded))}';
    if (_loaded.contains(key)) return;
    final existing = _inFlight[key];
    if (existing != null) return existing;
    final future = register(family, encoded);
    _inFlight[key] = future;
    try {
      await future;
      _loaded.add(key);
    } finally {
      _inFlight.remove(key);
    }
  }
}

final importedFonts = ImportedFontCache((family, encoded) async {
  final loader = FontLoader(family)
    ..addFont(Future.value(ByteData.sublistView(base64Decode(encoded))));
  await loader.load();
});

Future<void> cleanOldShareCards(Directory directory, {DateTime? now}) async {
  final cutoff = (now ?? DateTime.now()).subtract(const Duration(hours: 24));
  try {
    await for (final entry in directory.list(followLinks: false)) {
      if (entry is! File ||
          !RegExp(r'^shuye-share-\d+\.png$')
              .hasMatch(entry.uri.pathSegments.last)) {
        continue;
      }
      try {
        if ((await entry.lastModified()).isBefore(cutoff)) await entry.delete();
      } catch (_) {
        // Cache cleanup never prevents sharing.
      }
    }
  } catch (_) {
    // A missing or temporarily inaccessible cache directory is harmless.
  }
}

/// Delete only the just-created private copy when registration fails.
Future<void> registerAudioCopy(
  File copy,
  Future<void> Function() register,
) async {
  try {
    await register();
  } catch (_) {
    try {
      await copy.delete();
    } catch (_) {
      // Preserve the original database error.
    }
    rethrow;
  }
}
