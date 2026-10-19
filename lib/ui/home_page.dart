import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../models/share_item.dart';
import '../server/share_server.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final ShareServer _server = ShareServer(port: 8080);
  final TextEditingController _portController =
      TextEditingController(text: '8080');

  List<String> _lanIps = [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refreshLanIps();
  }

  @override
  void dispose() {
    _server.stop();
    _portController.dispose();
    super.dispose();
  }

  /// 枚举本机所有局域网 IPv4 地址（排除回环）
  Future<void> _refreshLanIps() async {
    try {
      final ifaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );
      final ips = <String>{};
      for (final iface in ifaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback && !addr.address.startsWith('169.254.')) {
            ips.add(addr.address);
          }
        }
      }
      if (mounted) setState(() => _lanIps = ips.toList()..sort());
    } catch (_) {
      // 网络接口枚举失败时静默，地址列表为空也能用 127.0.0.1
    }
  }

  String _baseUrl(String ip) => 'http://$ip:${_server.port}';

  Future<void> _toggleServer() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (_server.isRunning) {
        await _server.stop();
      } else {
        final port = int.tryParse(_portController.text.trim());
        if (port == null || port <= 0 || port > 65535) {
          _showSnack('端口不合法，请输入 1-65535 之间的数字');
          return;
        }
        _server.setPort(port);
        await _server.start();
        await _refreshLanIps();
      }
    } on SocketException catch (e) {
      _showSnack('启动失败：${e.message}（端口可能被占用）');
    } catch (e) {
      _showSnack('启动失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addFiles() async {
    try {
      final result = await FilePicker.platform.pickFiles(allowMultiple: true);
      final paths = result?.paths.whereType<String>().toList() ?? [];
      if (paths.isEmpty) return;
      setState(() {
        for (final p in paths) {
          _server.add(File(p));
        }
      });
      _showSnack('已添加 ${paths.length} 个文件');
    } catch (e) {
      _showSnack('添加文件失败：$e');
    }
  }

  Future<void> _addFolder() async {
    try {
      final path = await FilePicker.platform.getDirectoryPath();
      if (path == null || path.isEmpty) return;
      setState(() => _server.add(Directory(path)));
      _showSnack('已添加文件夹');
    } catch (e) {
      _showSnack('添加文件夹失败：$e');
    }
  }

  void _removeItem(ShareItem item) {
    setState(() => _server.remove(item.id));
  }

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) _showSnack('已复制到剪贴板');
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
          SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(),
                const SizedBox(height: 20),
                _buildServerCard(),
                const SizedBox(height: 20),
                _buildUrlCard(),
                const SizedBox(height: 20),
                _buildActions(),
                const SizedBox(height: 12),
                Expanded(child: _buildItemList()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---------------- 标题 ----------------

  Widget _buildHeader() {
    return Row(
      children: [
        Icon(Icons.share_rounded,
            size: 30, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 12),
        const Text(
          '文件共享 · FileShare',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: _server.isRunning
                ? Colors.green.withValues(alpha: 0.12)
                : Colors.grey.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _server.isRunning ? Icons.circle : Icons.circle_outlined,
                size: 12,
                color: _server.isRunning ? Colors.green : Colors.grey,
              ),
              const SizedBox(width: 6),
              Text(
                _server.isRunning ? '服务运行中' : '服务未启动',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _server.isRunning
                      ? Colors.green.shade800
                      : Colors.grey.shade700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ---------------- 服务器控制卡 ----------------

  Widget _buildServerCard() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Theme.of(context).dividerColor),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            const Icon(Icons.dns_outlined),
            const SizedBox(width: 12),
            const Text('HTTP 端口'),
            const SizedBox(width: 10),
            SizedBox(
              width: 90,
              child: TextField(
                controller: _portController,
                enabled: !_server.isRunning,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                  hintText: '8080',
                ),
                onSubmitted: (_) => _toggleServer(),
              ),
            ),
            const SizedBox(width: 16),
            FilledButton.icon(
              onPressed: _busy ? null : _toggleServer,
              icon: Icon(_server.isRunning ? Icons.stop : Icons.play_arrow),
              label: Text(_server.isRunning ? '停止服务' : '一键启动'),
            ),
            const Spacer(),
            if (_server.isRunning)
              Text(
                '累计请求：${_server.requestCount}',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              ),
          ],
        ),
      ),
    );
  }

  // ---------------- 访问地址卡 ----------------

  Widget _buildUrlCard() {
    final running = _server.isRunning;
    final primaryIp = _lanIps.isNotEmpty ? _lanIps.first : '127.0.0.1';
    final qrData = _baseUrl(primaryIp);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: running
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.5)
              : Theme.of(context).dividerColor,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.link,
                          size: 18,
                          color: running
                              ? Theme.of(context).colorScheme.primary
                              : Colors.grey),
                      const SizedBox(width: 6),
                      Text(
                        running ? '其他设备访问地址（同一局域网）' : '访问地址',
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (!running)
                    Text(
                      '启动服务后，这里会显示可访问的 HTTP 链接',
                      style:
                          TextStyle(color: Colors.grey.shade600, fontSize: 14),
                    )
                  else if (_lanIps.isEmpty)
                    Text(
                      '未检测到局域网 IP，请检查网络连接',
                      style:
                          TextStyle(color: Colors.orange.shade800, fontSize: 14),
                    )
                  else
                    ..._lanIps.map(
                      (ip) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: Theme.of(context)
                                    .colorScheme
                                    .primaryContainer
                                    .withValues(alpha: 0.35),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: SelectableText(
                                _baseUrl(ip),
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Theme.of(context).colorScheme.onSurface,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              tooltip: '复制链接',
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.copy, size: 18),
                              onPressed: () => _copy(_baseUrl(ip)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (running && _lanIps.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '手机 / 平板 / 其他电脑打开上面的地址即可浏览和下载共享内容',
                        style:
                            TextStyle(color: Colors.grey.shade600, fontSize: 12),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 20),
            // 二维码
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(color: Theme.of(context).dividerColor),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  QrImageView(
                    data: qrData,
                    version: QrVersions.auto,
                    size: 120,
                    backgroundColor: Colors.white,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    running ? '扫码打开' : '启动后可扫码',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------- 操作按钮 ----------------

  Widget _buildActions() {
    return Row(
      children: [
        OutlinedButton.icon(
          onPressed: _addFiles,
          icon: const Icon(Icons.insert_drive_file_outlined),
          label: const Text('添加文件'),
        ),
        const SizedBox(width: 12),
        OutlinedButton.icon(
          onPressed: _addFolder,
          icon: const Icon(Icons.create_new_folder_outlined),
          label: const Text('添加文件夹'),
        ),
        const SizedBox(width: 12),
        if (_server.items.isNotEmpty)
          Text(
            '共 ${_server.items.length} 项',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
          ),
      ],
    );
  }

  // ---------------- 共享列表 ----------------

  Widget _buildItemList() {
    final items = _server.items;
    if (items.isEmpty) {
      return Container(
        width: double.infinity,
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).dividerColor),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.folder_open_outlined,
                  size: 56, color: Colors.grey.shade400),
              const SizedBox(height: 12),
              Text(
                '还没有共享内容',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade600),
              ),
              const SizedBox(height: 6),
              Text(
                '点击上方「添加文件」或「添加文件夹」开始共享',
                style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          // 表头
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                const Expanded(
                    flex: 3,
                    child:
                        Text('名称', style: TextStyle(fontWeight: FontWeight.w600))),
                const SizedBox(
                    width: 90,
                    child: Text('类型/大小',
                        style: TextStyle(fontWeight: FontWeight.w600))),
                Expanded(
                    flex: 2,
                    child: Text('下载链接',
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade600))),
                const SizedBox(width: 40),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final item = items[index];
                return _buildItemRow(item);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemRow(ShareItem item) {
    final primaryIp = _lanIps.isNotEmpty ? _lanIps.first : '127.0.0.1';
    final url = '${_baseUrl(primaryIp)}/f/${item.id}';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Row(
              children: [
                Icon(
                  item.isFolder
                      ? Icons.folder_rounded
                      : Icons.insert_drive_file_rounded,
                  size: 20,
                  color: item.isFolder
                      ? Colors.amber.shade700
                      : Colors.blueGrey.shade400,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    item.name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 90,
            child: Text(
              item.sizeLabel,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
          ),
          Expanded(
            flex: 2,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    url,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '复制下载链接',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.copy, size: 16),
                  onPressed: () => _copy(url),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: '移除共享',
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.delete_outline,
                size: 18, color: Colors.red.shade300),
            onPressed: () => _removeItem(item),
          ),
        ],
      ),
    );
  }
}
