import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as digest;
import 'package:cryptography/cryptography.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

import 'models.dart';
import 'repository.dart';
import 'cloud_backends.dart';

class DeviceReader {
  static const channel = MethodChannel('dev.shuye/reader');
  static final events = StreamController<MethodCall>.broadcast();
  static bool initialized = false;
  static bool reading = false;
  static void initialize() {
    if (initialized) return;
    initialized = true;
    channel.setMethodCallHandler((call) async {
      events.add(call);
    });
  }

  static Future<T?> call<T>(String method, [dynamic args]) async {
    try {
      return await channel.invokeMethod<T>(method, args);
    } on MissingPluginException {
      return null;
    }
  }

  static Future<void> configure(ReaderSettings s, {bool reading = true}) async {
    DeviceReader.reading = reading;
    await call('configure', {
      'keepOn': reading && s.flag('reader.keepOn', true),
      'volumeKeys': reading && s.flag('reader.volumeKeys'),
      'brightness': reading ? s.number('reader.brightness', -1) : -1,
      'orientation': reading ? s.value('reader.orientation', 'auto') : 'auto',
    });
  }
}

class Secrets {
  static const storage = FlutterSecureStorage();
  Future<String> read(String key) async => await storage.read(key: key) ?? '';
  Future<void> write(String key, String value) async =>
      storage.write(key: key, value: value);
}

class BackupCipher {
  static final aes = AesGcm.with256bits();
  static final derivation = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: 150000,
    bits: 256,
  );
  static Future<String> encrypt(String plain, String password) =>
      Isolate.run(() => _encrypt(plain, password));
  static Future<String> _encrypt(String plain, String password) async {
    if (password.length < 8) throw const FormatException('备份密码至少 8 个字符');
    final salt = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    final key = await derivation.deriveKey(
      secretKey: SecretKey(utf8.encode(password)),
      nonce: salt,
    );
    final box = await aes.encrypt(utf8.encode(plain), secretKey: key);
    return jsonEncode({
      'app': 'shuye-encrypted',
      'version': 1,
      'kdf': 'pbkdf2-sha256',
      'iterations': 150000,
      'salt': base64Encode(salt),
      'nonce': base64Encode(box.nonce),
      'mac': base64Encode(box.mac.bytes),
      'data': base64Encode(box.cipherText),
    });
  }

  static Future<String> decrypt(String input, String password) =>
      Isolate.run(() => _decrypt(input, password));
  static Future<String> _decrypt(String input, String password) async {
    final j = jsonDecode(input) as Map<String, dynamic>;
    if (j['app'] != 'shuye-encrypted' ||
        j['version'] != 1 ||
        j['iterations'] != 150000) {
      throw const FormatException('加密备份格式不支持');
    }
    try {
      final salt = base64Decode(j['salt'] as String),
          nonce = base64Decode(j['nonce'] as String),
          mac = base64Decode(j['mac'] as String);
      if (salt.length != 16 || nonce.length != 12 || mac.length != 16) {
        throw const FormatException('加密参数无效');
      }
      final key = await derivation.deriveKey(
        secretKey: SecretKey(utf8.encode(password)),
        nonce: salt,
      );
      final plain = await aes.decrypt(
        SecretBox(
          base64Decode(j['data'] as String),
          nonce: nonce,
          mac: Mac(mac),
        ),
        secretKey: key,
      );
      return utf8.decode(plain);
    } on SecretBoxAuthenticationError {
      throw const FormatException('密码错误或备份已损坏');
    }
  }
}

Uri secureEndpoint(String url, {bool allowLocal = false}) {
  final uri = Uri.parse(url.trim());
  if (!uri.hasAuthority ||
      uri.userInfo.isNotEmpty ||
      (uri.scheme != 'https' &&
          !(allowLocal &&
              uri.scheme == 'http' &&
              (uri.host == 'localhost' || uri.host == '127.0.0.1')))) {
    throw const FormatException('请输入 HTTPS 地址（本机服务可使用 localhost HTTP）');
  }
  return uri;
}

// Close clients after every operation; redirects are disabled to protect credentials.
Future<http.Response> request(
  String method,
  Uri url, {
  Map<String, String> headers = const {},
  List<int>? body,
  http.Client? client,
}) async {
  final c = client ?? http.Client();
  try {
    final req = http.Request(method, url)..followRedirects = false;
    req.headers.addAll(headers);
    if (body != null) req.bodyBytes = body;
    final streamed = await c.send(req).timeout(const Duration(seconds: 45));
    final buffer = BytesBuilder();
    await for (final chunk in streamed.stream.timeout(
      const Duration(seconds: 45),
    )) {
      buffer.add(chunk);
      if (buffer.length > 80 * 1024 * 1024) {
        throw const FormatException('服务器返回内容超过 80 MB');
      }
    }
    final r = http.Response.bytes(
      buffer.takeBytes(),
      streamed.statusCode,
      headers: streamed.headers,
    );
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw HttpException('服务器返回 ${r.statusCode}，请检查地址、权限或凭据');
    }
    return r;
  } finally {
    if (client == null) c.close();
  }
}

class AiClient {
  final http.Client? client;
  AiClient({this.client});
  Future<String> answer({
    required String endpoint,
    required String key,
    required String model,
    required String prompt,
    required String context,
    String system = '你是阅读助手。引用原文时注明位置，不编造书中事实。',
  }) async {
    if (key.trim().isEmpty || model.trim().isEmpty) {
      throw const FormatException('请先设置 AI 密钥和模型');
    }
    final base = secureEndpoint(endpoint, allowLocal: true);
    final url = base.replace(
      path: '${base.path.replaceAll(RegExp(r'/+$'), '')}/chat/completions',
    );
    final response = await request(
      'POST',
      url,
      headers: {
        'Authorization': 'Bearer $key',
        'Content-Type': 'application/json',
      },
      body: utf8.encode(
        jsonEncode({
          'model': model,
          'messages': [
            {'role': 'system', 'content': system},
            {
              'role': 'user',
              'content':
                  '参考材料：\n${context.length > 30000 ? context.substring(0, 30000) : context}\n\n请求：$prompt',
            },
          ],
          'max_tokens': 2000,
        }),
      ),
      client: client,
    );
    final j =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    return ((j['choices'] as List).first as Map)['message']['content']
        as String;
  }
}

class KoReaderProgress {
  final http.Client? client;
  KoReaderProgress({this.client});
  Map<String, String> headers(String user, String password) => {
    'x-auth-user': user,
    'x-auth-key': digest.md5.convert(utf8.encode(password)).toString(),
    'Accept': 'application/vnd.koreader.v1+json',
    'Content-Type': 'application/json',
  };
  Future<double> download(
    String endpoint,
    String user,
    String password,
    String document,
  ) async {
    final base = secureEndpoint(endpoint);
    final response = await request(
      'GET',
      base.replace(
        path:
            '${base.path.replaceAll(RegExp(r'/+$'), '')}/syncs/progress/${Uri.encodeComponent(document)}',
      ),
      headers: headers(user, password),
      client: client,
    );
    final j = jsonDecode(utf8.decode(response.bodyBytes)) as Map;
    final percentage = (j['percentage'] as num).toDouble();
    if (!percentage.isFinite || percentage < 0 || percentage > 1) {
      throw const FormatException('远端进度无效');
    }
    return percentage;
  }

  Future<void> uploadPdf(
    String endpoint,
    String user,
    String password,
    String document,
    Book book,
  ) async {
    if (book.format != 'PDF') {
      throw const FormatException('文本书的定位方式不同，仅支持读取百分比；PDF 可以双向同步');
    }
    final base = secureEndpoint(endpoint);
    await request(
      'PUT',
      base.replace(
        path: '${base.path.replaceAll(RegExp(r'/+$'), '')}/syncs/progress',
      ),
      headers: headers(user, password),
      client: client,
      body: utf8.encode(
        jsonEncode({
          'document': document,
          'progress': '${book.metadata['pdfPage'] ?? 1}',
          'percentage': book.progress,
          'device': 'Shuye',
          'device_id': 'shuye-reader',
        }),
      ),
    );
  }

  static String filenameDigest(String name) =>
      digest.md5.convert(utf8.encode(name)).toString();
}

class SyncService {
  final ReaderRepository repo;
  final Secrets secrets;
  bool busy = false;
  SyncService(this.repo, this.secrets);
  Future<void> run(
    ReaderSettings s, {
    required bool download,
    required String password,
  }) async {
    if (busy) throw StateError('同步正在进行');
    busy = true;
    try {
      final provider = s.value('sync.provider', 'webdav');
      final cloud = ['onedrive', 'dropbox', 'googledrive'].contains(provider);
      final uri = cloud
          ? Uri.parse('https://localhost')
          : secureEndpoint(s.value('sync.endpoint', ''), allowLocal: true);
      final key = await secrets.read('sync.key');
      final user = s.value('sync.user', '');
      final payload = download
          ? null
          : utf8.encode(
              await BackupCipher.encrypt(await repo.backup(), password),
            );
      final headers = provider == 's3'
          ? s3Headers(
              download ? 'GET' : 'PUT',
              uri,
              payload ?? [],
              accessKey: user,
              secretKey: key,
              region: s.value('sync.region', 'us-east-1'),
            )
          : <String, String>{
              'Authorization':
                  'Basic ${base64Encode(utf8.encode('$user:$key'))}',
            };
      if (!download) headers['Content-Type'] = 'application/json';
      final bytes = cloud
          ? await CloudFiles().transfer(s, key, payload, download: download)
          : (await request(
              download ? 'GET' : 'PUT',
              uri,
              headers: headers,
              body: payload,
            )).bodyBytes;
      if (download) {
        await repo.restore(
          await BackupCipher.decrypt(utf8.decode(bytes), password),
        );
      }
      await repo.putEntry('syncHistory', {
        'direction': download ? 'download' : 'upload',
        'provider': provider,
        'ok': true,
        'at': DateTime.now().toIso8601String(),
      });
      if (download) {
        final restored = await repo.settings();
        for (final e in s.extra.entries.where(
          (e) => e.key.startsWith('sync.'),
        )) {
          restored.extra[e.key] = e.value;
        }
        await repo.saveSettings(restored);
      } else {
        await repo.saveSettings(s);
      }
    } catch (e) {
      await repo.putEntry('syncHistory', {
        'ok': false,
        'direction': download ? 'download' : 'upload',
        'at': DateTime.now().toIso8601String(),
        'error': e is HttpException ? e.message : '同步失败，请检查配置和备份密码',
      });
      rethrow;
    } finally {
      busy = false;
    }
  }
}

Map<String, String> s3Headers(
  String method,
  Uri uri,
  List<int> body, {
  required String accessKey,
  required String secretKey,
  required String region,
  DateTime? time,
}) {
  final iso = (time ?? DateTime.now()).toUtc().toIso8601String().replaceAll(
    RegExp(r'[-:]'),
    '',
  );
  final timestamp = '${iso.substring(0, 15)}Z',
      date = timestamp.substring(0, 8);
  final hash = digest.sha256.convert(body).toString();
  String awsEncode(String value) => Uri.encodeComponent(value).replaceAllMapped(
    RegExp(r"[!'()*]"),
    (m) => '%${m[0]!.codeUnitAt(0).toRadixString(16).toUpperCase()}',
  );
  final canonicalQuery =
      (uri.queryParametersAll.entries
              .expand(
                (e) =>
                    e.value.map((v) => '${awsEncode(e.key)}=${awsEncode(v)}'),
              )
              .toList()
            ..sort())
          .join('&');
  final canonicalPath = uri.path
      .split('/')
      .map((s) => awsEncode(Uri.decodeComponent(s)))
      .join('/');
  final host = uri.hasPort ? '${uri.host}:${uri.port}' : uri.host;
  final signed = 'host;x-amz-content-sha256;x-amz-date';
  final canonical =
      '$method\n${canonicalPath.isEmpty ? '/' : canonicalPath}\n$canonicalQuery\nhost:$host\nx-amz-content-sha256:$hash\nx-amz-date:$timestamp\n\n$signed\n$hash';
  final scope = '$date/$region/s3/aws4_request';
  final toSign =
      'AWS4-HMAC-SHA256\n$timestamp\n$scope\n${digest.sha256.convert(utf8.encode(canonical))}';
  List<int> hmac(List<int> key, String text) =>
      digest.Hmac(digest.sha256, key).convert(utf8.encode(text)).bytes;
  final signing = hmac(
    hmac(hmac(hmac(utf8.encode('AWS4$secretKey'), date), region), 's3'),
    'aws4_request',
  );
  final signature = hmac(
    signing,
    toSign,
  ).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return {
    'Host': host,
    'x-amz-content-sha256': hash,
    'x-amz-date': timestamp,
    'Authorization':
        'AWS4-HMAC-SHA256 Credential=$accessKey/$scope, SignedHeaders=$signed, Signature=$signature',
  };
}

List<Map<String, String>> parseOpds(String source, Uri base) {
  final doc = XmlDocument.parse(source);
  String text(XmlElement e, String name) =>
      e.childElements
          .where((c) => c.name.local == name)
          .firstOrNull
          ?.innerText
          .trim() ??
      '';
  return doc.descendants
      .whereType<XmlElement>()
      .where((e) => e.name.local == 'entry')
      .map((e) {
        final link = e.childElements
            .where(
              (c) =>
                  c.name.local == 'link' &&
                  (c.getAttribute('rel') ?? '').contains('acquisition'),
            )
            .firstOrNull;
        return {
          'title': text(e, 'title'),
          'author':
              e.descendants
                  .whereType<XmlElement>()
                  .where((c) => c.name.local == 'name')
                  .firstOrNull
                  ?.innerText ??
              '未知作者',
          'url': link == null
              ? ''
              : base.resolve(link.getAttribute('href') ?? '').toString(),
          'type': link?.getAttribute('type') ?? '',
        };
      })
      .where((e) => e['url']!.isNotEmpty)
      .toList();
}

class McpService {
  final ReaderRepository repo;
  HttpServer? server;
  String token = '';
  final Set<String> sessions = {};
  final Map<String, int> sessionRequests = {};
  McpService(this.repo);
  String get address =>
      server == null ? '' : 'http://127.0.0.1:${server!.port}/mcp';
  Future<void> start({bool lan = false}) async {
    if (server != null) return;
    token = base64UrlEncode(
      List<int>.generate(32, (_) => Random.secure().nextInt(256)),
    );
    server = await HttpServer.bind(
      lan ? InternetAddress.anyIPv4 : InternetAddress.loopbackIPv4,
      0,
    );
    server!.listen((r) {
      unawaited(handle(r));
    });
  }

  Future<void> stop() async {
    await server?.close(force: true);
    server = null;
    sessions.clear();
    sessionRequests.clear();
    token = '';
  }

  Future<void> handle(HttpRequest req) async {
    final res = req.response;
    try {
      if (req.uri.path != '/mcp') {
        res.statusCode = 404;
        return;
      }
      if (req.headers.value('authorization') != 'Bearer $token') {
        res.statusCode = 401;
        return;
      }
      if (req.headers.value('origin') != null) {
        res.statusCode = 403;
        return;
      }
      if (server?.address == InternetAddress.loopbackIPv4 &&
          !['127.0.0.1', 'localhost', '[::1]'].contains(req.headers.host)) {
        res.statusCode = 403;
        return;
      }
      if (req.method == 'GET') {
        res.statusCode = 405;
        return;
      }
      final version = req.headers.value('MCP-Protocol-Version');
      if (version != null &&
          !['2025-03-26', '2025-06-18', '2025-11-25'].contains(version)) {
        res.statusCode = 400;
        return;
      }
      if (req.method == 'DELETE') {
        final session = req.headers.value('Mcp-Session-Id');
        if (!sessions.remove(session)) {
          res.statusCode = 404;
          return;
        }
        sessionRequests.remove(session);
        res.statusCode = 204;
        return;
      }
      if (req.method != 'POST') {
        res.statusCode = 405;
        return;
      }
      final bytes = BytesBuilder();
      await for (final chunk in req.timeout(const Duration(seconds: 10))) {
        bytes.add(chunk);
        if (bytes.length > 65536) {
          res.statusCode = 413;
          return;
        }
      }
      final j =
          jsonDecode(utf8.decode(bytes.takeBytes())) as Map<String, dynamic>;
      final method = j['method'] as String;
      if (j['jsonrpc'] != '2.0') {
        res.statusCode = 400;
        return;
      }
      if (method != 'initialize') {
        final session = req.headers.value('Mcp-Session-Id');
        if (!sessions.contains(session)) {
          res.statusCode = 404;
          return;
        }
        sessionRequests[session!] = (sessionRequests[session] ?? 0) + 1;
        if (sessionRequests[session]! > 2000) {
          res.statusCode = 429;
          return;
        }
      }
      if (j['id'] == null) {
        res.statusCode = 202;
        return;
      }
      dynamic result;
      if (method == 'initialize') {
        final requested = (j['params'] as Map?)?['protocolVersion'];
        final negotiated =
            ['2025-03-26', '2025-06-18', '2025-11-25'].contains(requested)
            ? requested as String
            : '2025-11-25';
        {
          if (sessions.length >= 8) {
            res.statusCode = 429;
            return;
          }
          final id = base64UrlEncode(
            List<int>.generate(16, (_) => Random.secure().nextInt(256)),
          );
          sessions.add(id);
          res.headers.set('Mcp-Session-Id', id);
        }
        result = {
          'protocolVersion': negotiated,
          'capabilities': {'tools': {}},
          'serverInfo': {'name': 'shuye-reader', 'version': '0.2.0'},
        };
      } else if (method == 'ping') {
        result = {};
      } else if (method == 'tools/list') {
        result = {
          'tools': [
            for (final name in [
              'library',
              'notes',
              'statistics',
              'search',
              'propose_book_update',
            ])
              {
                'name': name,
                'description': {
                  'library': 'List local book titles and progress',
                  'notes': 'Read saved excerpts and notes',
                  'statistics': 'Read daily reading duration',
                  'search': 'Search book text',
                  'propose_book_update': 'Submit a book metadata change proposal for in-app human review; never applies changes directly',
                }[name],
                'inputSchema': {
                  'type': 'object',
                  'properties': name == 'propose_book_update'
                      ? {
                          'bookId': {'type': 'string'},
                          'changes': {
                            'type': 'object',
                            'properties': {
                              'title': {'type': 'string'},
                              'author': {'type': 'string'},
                              'category': {'type': 'string'},
                              'tags': {'type': 'string'},
                              'list': {'type': 'string'},
                              'rating': {
                                'type': 'number',
                                'minimum': 0,
                                'maximum': 5,
                              },
                              'review': {'type': 'string'},
                            },
                            'additionalProperties': false,
                          },
                        }
                      : name == 'search'
                      ? {
                          'query': {'type': 'string'},
                        }
                      : {},
                  if (name == 'search') 'required': ['query'],
                  if (name == 'propose_book_update')
                    'required': ['bookId', 'changes'],
                },
                'annotations': {
                  'readOnlyHint': name != 'propose_book_update',
                  'destructiveHint': false,
                },
              },
          ],
        };
      } else if (method == 'tools/call') {
        final p = Map<String, dynamic>.from(j['params'] as Map),
            name = p['name'];
        dynamic data;
        if (name == 'propose_book_update') {
          final args = Map<String, dynamic>.from(p['arguments'] as Map);
          data = {
            'proposalId': await repo.proposeBookUpdate(
              args['bookId'] as String,
              Map<String, dynamic>.from(args['changes'] as Map),
            ),
            'status': 'pending_review',
          };
        } else if (name == 'library') {
          data = [
            for (final b in await repo.books(summaries: true))
              {
                'id': b.id,
                'title': b.title,
                'author': b.author,
                'progress': b.progress,
              },
          ];
        } else if (name == 'notes') {
          data = (await repo.notes()).map((n) => n.toJson()).toList();
        } else if (name == 'statistics') {
          data = await repo.statistics();
        } else if (name == 'search') {
          final q = (p['arguments'] as Map?)?['query'] as String? ?? '';
          if (q.isEmpty || q.length > 100) {
            throw const FormatException('查询长度 1–100');
          }
          data = <Map<String, dynamic>>[];
          for (final summary in await repo.books(summaries: true)) {
            final b = await repo.book(summary.id);
            for (var i = 0; i < b.chapters.length; i++) {
              final at = b.chapters[i].text.indexOf(q);
              if (at >= 0 && (data as List).length < 100) {
                data.add({
                  'book': b.title,
                  'chapter': i,
                  'offset': at,
                  'excerpt': b.chapters[i].text.substring(
                    max(0, at - 40),
                    min(b.chapters[i].text.length, at + q.length + 80),
                  ),
                });
              }
            }
          }
        } else {
          throw const FormatException('未知工具');
        }
        result = {
          'content': [
            {'type': 'text', 'text': jsonEncode(data)},
          ],
        };
      } else {
        res.headers.contentType = ContentType.json;
        res.write(
          jsonEncode({
            'jsonrpc': '2.0',
            'id': j['id'],
            'error': {'code': -32601, 'message': 'Method not found'},
          }),
        );
        return;
      }
      res.headers.contentType = ContentType.json;
      res.write(
        jsonEncode({'jsonrpc': '2.0', 'id': j['id'], 'result': result}),
      );
    } catch (_) {
      res.statusCode = 400;
    } finally {
      await res.close();
    }
  }
}
