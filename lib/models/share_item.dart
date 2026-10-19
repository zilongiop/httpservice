/// 共享项类型
enum ShareType { file, folder }

/// 一个被共享的文件或文件夹
class ShareItem {
  final String id;
  final String path;
  final String name;
  final ShareType type;
  final int sizeBytes;
  final DateTime addedAt;

  const ShareItem({
    required this.id,
    required this.path,
    required this.name,
    required this.type,
    required this.sizeBytes,
    required this.addedAt,
  });

  bool get isFolder => type == ShareType.folder;

  /// 展示用的大小 / 类型标签
  String get sizeLabel =>
      isFolder ? '文件夹' : _formatSize(sizeBytes);

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
