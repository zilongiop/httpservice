import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http_service/server/share_server.dart';

/// 对 ShareServer 核心做真实的功能验证：
/// 启动服务 → 添加文件/文件夹 → 通过 HTTP 请求验证下载、浏览、安全和 404。
void main() {
  late ShareServer server;
  late Directory tempDir;
  late File sampleFile;
  late Directory sampleFolder;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('share_server_test');
    sampleFile = File('${tempDir.path}/示例文档.txt')
      ..writeAsStringSync('hello 文件共享 123');
    sampleFolder = Directory('${tempDir.path}/子目录')..createSync();
    File('${sampleFolder.path}/内层文件.bin').writeAsBytesSync([1, 2, 3, 4, 5]);

    server = ShareServer(port: 0);
    await server.start();
  });

  tearDownAll(() async {
    await server.stop();
    await tempDir.delete(recursive: true);
  });

  test('端口绑定成功且服务运行', () {
    expect(server.isRunning, isTrue);
    expect(server.port, greaterThan(0));
  });

  test('索引页列出共享文件', () async {
    final id = server.add(sampleFile);
    final client = HttpClient();
    try {
      final req = await client.getUrl(Uri.parse('http://127.0.0.1:${server.port}/'));
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      expect(res.statusCode, 200);
      expect(body, contains('示例文档.txt'));
      expect(body, contains('/f/$id'));
    } finally {
      client.close();
    }
  });

  test('文件下载内容与 Content-Disposition 正确', () async {
    final id = server.add(sampleFile);
    final client = HttpClient();
    try {
      final req = await client.getUrl(
          Uri.parse('http://127.0.0.1:${server.port}/f/$id'));
      final res = await req.close();
      final bytes = await res.fold<List<int>>([], (a, b) => a..addAll(b));
      expect(res.statusCode, 200);
      expect(utf8.decode(bytes), 'hello 文件共享 123');
      final disposition = res.headers.value('content-disposition');
      expect(disposition, contains('attachment'));
      expect(disposition, contains('filename*'));
    } finally {
      client.close();
    }
  });

  test('inline 参数允许浏览器直接打开', () async {
    final id = server.add(sampleFile);
    final client = HttpClient();
    try {
      final req = await client.getUrl(
          Uri.parse('http://127.0.0.1:${server.port}/f/$id?inline=1'));
      final res = await req.close();
      expect(res.headers.value('content-disposition'), 'inline');
      await res.drain<void>();
    } finally {
      client.close();
    }
  });

  test('文件夹浏览与子文件下载', () async {
    final id = server.add(sampleFolder);
    // 关闭自动跟随重定向，以便验证 302
    final client = HttpClient();
    try {
      // 根文件夹：302 重定向补斜杠
      var req = await client.getUrl(
          Uri.parse('http://127.0.0.1:${server.port}/f/$id'));
      req.followRedirects = false;
      var res = await req.close();
      expect(res.statusCode, 302);
      expect(res.headers.value('location'), '/f/$id/');
      await res.drain<void>();

      // 浏览页
      req = await client.getUrl(
          Uri.parse('http://127.0.0.1:${server.port}/f/$id/'));
      res = await req.close();
      final listing = await res.transform(utf8.decoder).join();
      expect(res.statusCode, 200);
      expect(listing, contains('内层文件.bin'));

      // 子文件下载
      req = await client.getUrl(Uri.parse(
          'http://127.0.0.1:${server.port}/f/$id/%E5%86%85%E5%B1%82%E6%96%87%E4%BB%B6.bin'));
      res = await req.close();
      final bytes = await res.fold<List<int>>([], (a, b) => a..addAll(b));
      expect(res.statusCode, 200);
      expect(bytes, [1, 2, 3, 4, 5]);
    } finally {
      client.close();
    }
  });

  test('未知 id 返回 404', () async {
    final client = HttpClient();
    try {
      final req = await client.getUrl(
          Uri.parse('http://127.0.0.1:${server.port}/f/not_exist_1'));
      final res = await req.close();
      expect(res.statusCode, 404);
      await res.drain<void>();
    } finally {
      client.close();
    }
  });

  test('路径穿越被拒绝 (403)', () async {
    final id = server.add(sampleFolder);
    // Uri.parse 会自行规范化 ".."，因此用原始 Socket 发送未规范化的请求，
    // 以真实验证服务器端的穿越防护。
    final socket = await Socket.connect('127.0.0.1', server.port);
    socket.write(
      'GET /f/$id/../%E7%A4%BA%E4%BE%8B%E6%96%87%E6%A1%A3.txt HTTP/1.1\r\n'
      'Host: 127.0.0.1\r\nConnection: close\r\n\r\n',
    );
    final responseBytes = await socket
        .fold<List<int>>([], (a, b) => a..addAll(b))
        .timeout(const Duration(seconds: 5));
    final response = utf8.decode(responseBytes);
    await socket.close();
    // HttpServer 的 URI 解析会规范化 ".."，逃逸请求不可能命中共享目录外的文件；
    // 服务器自身也有 ".." 防护，因此响应必须是 403 或 404，绝不能是 200。
    final statusLine = response.split('\r\n').first;
    expect(
      statusLine == 'HTTP/1.1 403 Forbidden' ||
          statusLine == 'HTTP/1.1 404 Not Found',
      isTrue,
      reason: '路径穿越请求应被拒绝，实际: $statusLine',
    );
    expect(response.contains('hello 文件共享 123'), isFalse,
        reason: '穿越请求不应返回共享目录外的文件内容');
  });
}
