// 笔记应用入口
//
// 这是一个支持富文本和 Markdown 的跨平台笔记应用。
// 支持平台：Windows、Android、Web

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'services/note_storage_service.dart';
import 'screens/home_screen.dart';

/// 应用入口函数
///
/// 初始化流程：
/// 1. 确保 Flutter 绑定初始化
/// 2. 初始化 Hive 本地存储
/// 3. 创建并初始化存储服务
/// 4. 启动应用
void main() async {
  // 确保 Flutter 绑定已初始化（异步操作前必须调用）
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化 Hive 本地存储引擎
  await Hive.initFlutter();

  // 创建并初始化笔记存储服务
  final storageService = NoteStorageService();
  await storageService.init();

  // 启动应用
  runApp(NoteApp(storageService: storageService));
}

/// 笔记应用主组件
///
/// 使用 MaterialApp 构建，配置了：
/// - Material Design 3 主题
/// - 明暗主题自动切换
/// - 多语言支持（包括 flutter_quill 本地化）
class NoteApp extends StatelessWidget {
  /// 笔记存储服务实例
  final NoteStorageService storageService;

  const NoteApp({super.key, required this.storageService});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '笔记',
      debugShowCheckedModeBanner: false,

      // 配置本地化代理，支持中文和 flutter_quill 的本地化
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        FlutterQuillLocalizations.delegate,
      ],
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [
        Locale('zh', 'CN'),
        Locale('en', 'US'),
      ],

      // 亮色主题配置
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(centerTitle: true, elevation: 0),
      ),

      // 暗色主题配置
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),

      // 跟随系统主题模式
      themeMode: ThemeMode.system,

      // 首页：笔记列表
      home: HomeScreen(storageService: storageService),
    );
  }
}
