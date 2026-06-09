import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'services/note_storage_service.dart';
import 'services/clipper/extractor_registry.dart';
import 'services/clipper/readability_extractor.dart';
import 'services/clipper/template_rule.dart';
import 'services/clipper/template_extractor.dart';
import 'services/clipper/extractors/zhihu_extractor.dart';
import 'services/clipper/extractors/zhihu_zhuanlan_extractor.dart';
import 'services/clipper/extractors/xhs_extractor.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final storageService = NoteStorageService();
  await storageService.init();

  // 初始化剪藏提取器注册中心
  await _initClipperRegistry();

  runApp(NoteApp(storageService: storageService));
}

Future<void> _initClipperRegistry() async {
  final registry = ExtractorRegistry.instance;

  // 注册专用提取器
  registry.register(ZhihuExtractor());
  registry.register(ZhihuZhuanlanExtractor());
  registry.register(XhsExtractor());

  // 注册规则模板提取器
  final rules = await RuleLoader.loadRules();
  for (final rule in rules) {
    registry.register(TemplateExtractor(rule));
  }

  // 注册 Readability 通用兜底
  registry.register(ReadabilityExtractor());
}

class NoteApp extends StatelessWidget {
  final NoteStorageService storageService;

  const NoteApp({super.key, required this.storageService});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '笔记',
      debugShowCheckedModeBanner: false,
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
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(centerTitle: true, elevation: 0),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: ThemeMode.system,
      home: HomeScreen(storageService: storageService),
    );
  }
}
