import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'ui/home_page.dart';

/// 窗口默认尺寸与最小尺寸
const Size _kDefaultWindowSize = Size(1000, 720);
const Size _kMinWindowSize = Size(900, 700);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化窗口管理器（设置默认尺寸、最小尺寸、标题）
  await windowManager.ensureInitialized();
  const windowOptions = WindowOptions(
    size: _kDefaultWindowSize,
    minimumSize: _kMinWindowSize,
    center: true,
    title: '文件共享',
    titleBarStyle: TitleBarStyle.normal,
  );
  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(const FileShareApp());
}

class FileShareApp extends StatelessWidget {
  const FileShareApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '文件共享',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const HomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}
