import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'services.dart';

/// Temporary, download-only transfer of an encrypted snapshot. No library edit
/// endpoint, directory listing or file-path parameter is exposed.
class LanBackup {
  HttpServer? server;
  Timer? expiry;
  String token = '';
  List<int> payload = [];
  int downloads = 0;
  int generation = 0;
  Future<void> start(
    String snapshot,
    String password, {
    InternetAddress? address,
  }) async {
    if (server != null) throw StateError('传输已启动');
    final ticket = generation;
    final encrypted = utf8.encode(
      await BackupCipher.encrypt(snapshot, password),
    );
    if (ticket != generation) throw StateError('传输已取消');
    payload = encrypted;
    token = base64UrlEncode(
      List<int>.generate(32, (_) => Random.secure().nextInt(256)),
    );
    downloads = 0;
    server = await HttpServer.bind(address ?? InternetAddress.anyIPv4, 0);
    if (ticket != generation) {
      await stop();
      throw StateError('传输已取消');
    }
    expiry = Timer(const Duration(minutes: 10), () => unawaited(stop()));
    server!.listen((request) {
      unawaited(handle(request));
    });
  }

  Future<List<String>> urls() async {
    if (server == null) return [];
    final port = server!.port;
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
    );
    final ips = interfaces
        .expand((i) => i.addresses)
        .where(
          (a) =>
              a.address.startsWith('192.168.') ||
              a.address.startsWith('10.') ||
              (a.address.startsWith('172.') &&
                  int.tryParse(a.address.split('.')[1]) != null &&
                  int.parse(a.address.split('.')[1]) >= 16 &&
                  int.parse(a.address.split('.')[1]) <= 31),
        );
    return [
      for (final ip in ips) 'http://${ip.address}:$port/backup?key=$token',
    ];
  }

  Future<void> handle(HttpRequest request) async {
    final response = request.response;
    try {
      if (request.method != 'GET' || request.uri.path != '/backup') {
        response.statusCode = 404;
        return;
      }
      if (request.uri.queryParameters['key'] != token ||
          token.isEmpty ||
          request.headers.value('origin') != null) {
        response.statusCode = 403;
        return;
      }
      if (downloads >= 3) {
        response.statusCode = 429;
        return;
      }
      downloads++;
      response.headers.contentType = ContentType.json;
      response.headers.set(
        'Content-Disposition',
        'attachment; filename="shuye-encrypted-backup.json"',
      );
      response.headers.set('Cache-Control', 'no-store');
      response.headers.set('X-Content-Type-Options', 'nosniff');
      response.contentLength = payload.length;
      response.add(payload);
    } finally {
      await response.close();
    }
  }

  Future<void> stop() async {
    generation++;
    expiry?.cancel();
    expiry = null;
    final active = server;
    server = null;
    token = '';
    payload = [];
    await active?.close(force: true);
  }
}
