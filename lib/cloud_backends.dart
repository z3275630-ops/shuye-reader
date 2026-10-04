import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';
import 'services.dart';

class CloudFiles {
  final http.Client? client;
  CloudFiles({this.client});
  String asciiJson(Object value) => jsonEncode(value)
      .split('')
      .map(
        (c) => c.codeUnitAt(0) > 127
            ? '\\u${c.codeUnitAt(0).toRadixString(16).padLeft(4, '0')}'
            : c,
      )
      .join();
  Future<List<int>> transfer(
    ReaderSettings s,
    String token,
    List<int>? payload, {
    required bool download,
  }) async {
    if (token.isEmpty) throw const FormatException('请填写云盘访问令牌');
    final provider = s.value('sync.provider', '');
    final headers = {'Authorization': 'Bearer $token'};
    if (provider == 'dropbox') {
      final path = s.value('sync.path', '/shuye-backup.json');
      if (!path.startsWith('/')) {
        throw const FormatException('Dropbox 路径需以 / 开头');
      }
      headers['Dropbox-API-Arg'] = asciiJson(
        download
            ? {'path': path}
            : {
                'path': path,
                'mode': 'overwrite',
                'autorename': false,
                'mute': true,
              },
      );
      if (!download) headers['Content-Type'] = 'application/octet-stream';
      final r = await request(
        'POST',
        Uri.parse(
          'https://content.dropboxapi.com/2/files/${download ? 'download' : 'upload'}',
        ),
        headers: headers,
        body: payload,
        client: client,
      );
      return r.bodyBytes;
    }
    if (provider == 'onedrive') {
      final path = s
          .value('sync.path', '/shuye-backup.json')
          .split('/')
          .map(Uri.encodeComponent)
          .join('/');
      final root = Uri.parse(
        'https://graph.microsoft.com/v1.0/me/drive/root:$path:',
      );
      if (download) {
        final r = await request('GET', root, headers: headers, client: client);
        final url =
            (jsonDecode(utf8.decode(r.bodyBytes))
                    as Map)['@microsoft.graph.downloadUrl']
                as String?;
        if (url == null) throw const FormatException('OneDrive 文件没有下载地址');
        final bytes = await request('GET', secureEndpoint(url), client: client);
        return bytes.bodyBytes;
      }
      headers['Content-Type'] = 'application/octet-stream';
      final r = await request(
        'PUT',
        Uri.parse('$root/content'),
        headers: headers,
        body: payload,
        client: client,
      );
      return r.bodyBytes;
    }
    if (provider == 'googledrive') {
      final id = s.value('sync.fileId', '');
      if (download) {
        if (id.isEmpty) {
          throw const FormatException('请先填写 Google Drive 文件 ID 或上传一次');
        }
        final r = await request(
          'GET',
          Uri.https('www.googleapis.com', '/drive/v3/files/$id', {
            'alt': 'media',
          }),
          headers: headers,
          client: client,
        );
        return r.bodyBytes;
      }
      final init = await request(
        id.isEmpty ? 'POST' : 'PATCH',
        Uri.https(
          'www.googleapis.com',
          '/upload/drive/v3/files${id.isEmpty ? '' : '/$id'}',
          {'uploadType': 'resumable'},
        ),
        headers: {
          ...headers,
          'Content-Type': 'application/json; charset=UTF-8',
          'X-Upload-Content-Type': 'application/json',
          'X-Upload-Content-Length': '${payload!.length}',
        },
        body: utf8.encode(
          jsonEncode(id.isEmpty ? {'name': 'shuye-backup.json'} : {}),
        ),
        client: client,
      );
      final location = init.headers['location'];
      if (location == null) throw const FormatException('Google Drive 未返回上传地址');
      final uri = secureEndpoint(location);
      if (uri.host != 'www.googleapis.com') {
        throw const FormatException('Google Drive 上传地址无效');
      }
      final result = await request(
        'PUT',
        uri,
        headers: {...headers, 'Content-Type': 'application/json'},
        body: payload,
        client: client,
      );
      final metadata = jsonDecode(utf8.decode(result.bodyBytes)) as Map;
      s.extra['sync.fileId'] = metadata['id'] as String;
      return result.bodyBytes;
    }
    throw const FormatException('云盘后端未配置');
  }
}
