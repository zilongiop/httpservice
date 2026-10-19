import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:mime/mime.dart';

import '../models/share_item.dart';

const _idChars =
    'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';

/// 本地 HTTP 文件共享服务器。
///
/// - 根路径 `/` 返回索引页，列出全部共享项及其链接
/// - `/f/<id>` 下载文件或浏览文件夹
/// - `/f/<id>/<子路径>` 访问文件夹内的文件 / 子目录
/// - `/f/<id>?inline=1` 以 inline 方式在浏览器中直接打开文件
class ShareServer {
  HttpServer? _server;
  final List<ShareItem> _items = [];
  final Map<String, ShareItem> _byId = {};
  final Random _random = Random();

  int _port;
  int _requestCount = 0;

  ShareServer({int port = 8080}) : _port = port;

  bool get isRunning => _server != null;

  /// 实际监听端口（端口为 0 时返回系统分配的随机端口）
  int get port => _server?.port ?? _port;
  int get requestCount => _requestCount;
  List<ShareItem> get items => List.unmodifiable(_items);

  /// 仅在服务器未启动时允许修改端口
  void setPort(int port) {
    if (_server == null) _port = port;
  }

  /// 一键启动：绑定所有 IPv4 网卡，监听指定端口
  Future<void> start() async {
    if (_server != null) return;
    _server = await HttpServer.bind(InternetAddress.anyIPv4, _port);
    _server!.listen(
      _handleRequest,
      onError: (Object _) {
        // 单个连接错误不影响整体服务
      },
    );
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  /// 添加一个共享文件或文件夹，返回其短 id
  String add(FileSystemEntity entity) {
    final isDir = FileSystemEntity.isDirectorySync(entity.path);
    final name = entity.path.split(Platform.pathSeparator).last;
    final size = isDir ? 0 : File(entity.path).lengthSync();
    final item = ShareItem(
      id: _newId(),
      path: entity.path,
      name: name,
      type: isDir ? ShareType.folder : ShareType.file,
      sizeBytes: size,
      addedAt: DateTime.now(),
    );
    _items.add(item);
    _byId[item.id] = item;
    return item.id;
  }

  void remove(String id) {
    final item = _byId.remove(id);
    if (item != null) _items.remove(item);
  }

  String _newId() {
    String id;
    do {
      id = List.generate(
        8,
        (_) => _idChars[_random.nextInt(_idChars.length)],
      ).join();
    } while (_byId.containsKey(id));
    return id;
  }

  // ---------------------------------------------------------------------
  // 请求处理
  // ---------------------------------------------------------------------

  Future<void> _handleRequest(HttpRequest request) async {
    _requestCount++;
    final response = request.response;
    try {
      final path = request.uri.path;
      if (path == '/' || path == '/index.html') {
        await _serveIndex(request);
        return;
      }
      if (path.startsWith('/f/')) {
        await _serveShared(request);
        return;
      }
      await _sendPage(request, HttpStatus.notFound, '404 Not Found',
          '<p>页面不存在。</p>');
    } catch (e) {
      try {
        response.statusCode = HttpStatus.internalServerError;
        await _sendPage(
            request, HttpStatus.internalServerError, '500 服务器错误',
            '<p>${_escape(e.toString())}</p>');
      } catch (_) {
        // 响应可能已经关闭，忽略
      }
    }
  }

  /// 索引页：列出所有共享项
  Future<void> _serveIndex(HttpRequest request) async {
    final sb = StringBuffer();
    sb.writeln('<h1>📁 文件共享</h1>');
    if (_items.isEmpty) {
      sb.writeln('<p class="empty">还没有共享任何内容，请回到应用添加文件或文件夹。</p>');
    } else {
      sb.writeln('<ul class="list">');
      for (final item in _items) {
        final href = '/f/${item.id}';
        final icon = item.isFolder ? '📂' : '📄';
        final label = item.isFolder ? '文件夹' : item.sizeLabel;
        sb.writeln(
          '<li><span class="icon">$icon</span>'
          '<a href="$href">${_escape(item.name)}</a>'
          '<span class="meta">$label</span>'
          '<a class="btn" href="$href" download>下载</a>'
          '</li>',
        );
      }
      sb.writeln('</ul>');
    }
    await _sendPage(request, HttpStatus.ok, '文件共享', sb.toString());
  }

  /// 处理 /f/<id>[/子路径]
  Future<void> _serveShared(HttpRequest request) async {
    // 用 pathSegments 解析：它是已解码的段（uri.path 保留百分号编码）
    final segs = request.uri.pathSegments;
    if (segs.length < 2) {
      await _sendPage(
          request, HttpStatus.notFound, '404 Not Found', '<p>内容不存在。</p>');
      return;
    }

    final item = _byId[segs[1]];
    if (item == null) {
      await _sendPage(
          request, HttpStatus.notFound, '404 Not Found', '<p>内容不存在。</p>');
      return;
    }

    final subSegs = segs.sublist(2);
    // 路径穿越防护：拒绝 .. 及异常字符
    for (final s in subSegs) {
      if (s == '..' || s.contains(':') || s.contains('\\') || s.contains('/')) {
        await _sendPage(
            request, HttpStatus.forbidden, '403 Forbidden', '<p>非法路径。</p>');
        return;
      }
    }

    var targetPath = item.path;
    if (subSegs.isNotEmpty) {
      targetPath =
          '${item.path}${Platform.pathSeparator}${subSegs.join(Platform.pathSeparator)}';
    }

    final entityType = FileSystemEntity.typeSync(targetPath);
    if (entityType == FileSystemEntityType.notFound) {
      await _sendPage(
          request, HttpStatus.notFound, '404 Not Found', '<p>内容不存在。</p>');
      return;
    }

    if (entityType == FileSystemEntityType.directory) {
      // 文件夹：若缺少结尾斜杠则重定向，保证相对链接可用
      if (!request.uri.path.endsWith('/')) {
        request.response.statusCode = HttpStatus.movedTemporarily;
        request.response.headers
            .set(HttpHeaders.locationHeader, '${request.uri.path}/');
        await request.response.close();
        return;
      }
      await _serveDirectory(request, item, subSegs, Directory(targetPath));
    } else {
      final inline = request.uri.queryParameters['inline'] == '1';
      await _serveFile(request, File(targetPath), inline: inline);
    }
  }

  /// 文件下载 / 在线访问
  Future<void> _serveFile(
    HttpRequest request,
    File file, {
    required bool inline,
  }) async {
    final response = request.response;
    final name = file.path.split(Platform.pathSeparator).last;
    final size = file.lengthSync();
    final mimeType =
        lookupMimeType(file.path) ?? 'application/octet-stream';

    response.headers.contentType = ContentType.parse(mimeType);
    response.headers.contentLength = size;
    if (inline) {
      response.headers.set('content-disposition', 'inline');
    } else {
      // RFC 5987：UTF-8 编码文件名，中文文件名不乱码
      response.headers.set(
        'content-disposition',
        "attachment; filename*=UTF-8''${Uri.encodeComponent(name)}",
      );
    }
    await response.addStream(file.openRead());
    await response.close();
  }

  /// 文件夹浏览页
  Future<void> _serveDirectory(
    HttpRequest request,
    ShareItem root,
    List<String> subSegs,
    Directory dir,
  ) async {
    final entries = dir.listSync().toList()..sort(_compareEntries);

    final baseUrl = '/f/${root.id}'
        '${subSegs.isEmpty ? '' : '/${subSegs.join('/')}'}/';

    final sb = StringBuffer();
    sb.writeln('<h1>📂 ${_escape(root.name)}</h1>');
    if (subSegs.isNotEmpty) {
      sb.writeln('<p><a href="/f/${root.id}/">← 返回上级</a></p>');
    }
    if (entries.isEmpty) {
      sb.writeln('<p class="empty">这个文件夹是空的。</p>');
    } else {
      sb.writeln('<ul class="list">');
      for (final e in entries) {
        final isDir = e is Directory;
        final childName = e.path.split(Platform.pathSeparator).last;
        final encoded = Uri.encodeComponent(childName);
        final href = '$baseUrl$encoded';
        final icon = isDir ? '📂' : '📄';
        final meta = isDir
            ? '文件夹'
            : _formatSize((e as File).lengthSync());
        final downloadAttr = isDir ? '' : ' download';
        sb.writeln(
          '<li><span class="icon">$icon</span>'
          '<a href="$href">${_escape(childName)}</a>'
          '<span class="meta">$meta</span>'
          '<a class="btn" href="$href"$downloadAttr>${isDir ? '打开' : '下载'}</a>'
          '</li>',
        );
      }
      sb.writeln('</ul>');
    }
    await _sendPage(request, HttpStatus.ok, root.name, sb.toString());
  }

  int _compareEntries(FileSystemEntity a, FileSystemEntity b) {
    final aDir = a is Directory;
    final bDir = b is Directory;
    if (aDir != bDir) return aDir ? -1 : 1;
    return a.path.toLowerCase().compareTo(b.path.toLowerCase());
  }

  // ---------------------------------------------------------------------
  // 页面渲染
  // ---------------------------------------------------------------------

  Future<void> _sendPage(
    HttpRequest request,
    int status,
    String title,
    String body,
  ) async {
    final response = request.response;
    response.statusCode = status;
    response.headers.contentType = ContentType.html;
    response.write(_page(title, body));
    await response.close();
  }

  String _page(String title, String body) {
    return '''
<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${_escape(title)} · 文件共享</title>
<style>
  body { font-family: -apple-system, "PingFang SC", "Microsoft YaHei", sans-serif;
         max-width: 860px; margin: 40px auto; padding: 0 20px; color: #24292f; }
  h1 { font-size: 24px; }
  .empty { color: #6e7781; }
  ul.list { list-style: none; padding: 0; }
  ul.list li { display: flex; align-items: center; gap: 12px;
               padding: 12px 14px; border: 1px solid #d0d7de;
               border-radius: 8px; margin-bottom: 8px;
               background: #fff; }
  ul.list li .icon { font-size: 20px; }
  ul.list li a { color: #0969da; text-decoration: none; font-weight: 600;
                 overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  ul.list li a:hover { text-decoration: underline; }
  ul.list li .meta { color: #6e7781; font-size: 13px; margin-left: auto;
                     white-space: nowrap; }
  ul.list li .btn { font-weight: 500; font-size: 13px;
                    border: 1px solid #d0d7de; border-radius: 6px;
                    padding: 4px 12px; color: #24292f !important;
                    text-decoration: none !important; }
  ul.list li .btn:hover { background: #f6f8fa; }
</style>
</head>
<body>
$body
</body>
</html>
''';
  }

  static String _escape(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#39;');

  static String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}
