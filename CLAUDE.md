# Note - Flutter 笔记应用

一个 Flutter 笔记应用。

## 项目信息

- **Flutter SDK**: ^3.11.0
- **支持平台**: Android、Web、Windows

## 常用命令

```bash
# 获取依赖
flutter pub get

# 运行应用（调试模式）
flutter run

# 指定平台运行
flutter run -d windows    # Windows 桌面
flutter run -d chrome     # Web 浏览器

# 生产环境构建
flutter build windows     # Windows
flutter build web         # Web
flutter build apk         # Android

# 运行测试
flutter test

# 代码分析
flutter analyze
```

## 项目结构

```
lib/
  main.dart          # 应用入口
android/             # Android 平台代码
web/                 # Web 平台代码
windows/             # Windows 平台代码
test/                # 单元测试
```

## 代码规范

- 遵循 Flutter/Dart 编码规范
- 使用 `flutter_lints` 包的 lint 规则
- 保持组件小而专注
- 尽可能使用 const 构造函数


使用中文回答
