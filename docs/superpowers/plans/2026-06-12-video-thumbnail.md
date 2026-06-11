# 视频缩略图预生成 实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 在视频插入时使用 media_kit Player.screenshot() 预生成 JPEG 缩略图，编辑器和列表直接显示缩略图消除延迟。

**架构：** VideoStorageService 新增 generateThumbnail 方法负责截帧和保存。视频 BlockEmbed JSON 增加 thumbnail 字段。编辑器 _VideoEmbedBuilder 优先显示缩略图+播放按钮，点击后切换为 media_kit 播放器。列表的 MediaInfo 扩展 thumbnail 字段。

**技术栈：** media_kit Player.screenshot()、dart:io File、现有 VideoStorageService / ImageStorageService 模式

---

## 文件结构

| 文件 | 变更 | 职责 |
|------|------|------|
| `lib/services/video_storage_service.dart` | 修改 | 新增 `generateThumbnail`、`deleteVideo` 联动删除缩略图 |
| `lib/utils/media_thumbnail.dart` | 修改 | `MediaInfo` 增加 `thumbnail` 字段，`extractFirstMedia` 提取 thumbnail |
| `lib/widgets/rich_text_editor.dart` | 修改 | `_insertVideo`/`_insertVideoUrl` 调用截帧；`_VideoEmbedBuilder` 缩略图优先显示；新增 `_VideoThumbnailWidget` |
| `lib/screens/home_screen.dart` | 修改 | `_buildListThumbnail`/`_buildWaterfallThumbnail` 优先使用 thumbnail |

---

### 任务 1：VideoStorageService 新增 generateThumbnail 方法

**文件：**
- 修改：`lib/services/video_storage_service.dart`

- [ ] **步骤 1：添加 generateThumbnail 方法**

在 `VideoStorageService` 类中新增方法。在 `saveVideo` 方法之后添加：

```dart
import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:media_kit/media_kit.dart';
```

```dart
/// 从视频中截取缩略图并保存为 JPEG 文件。
///
/// [source] 视频文件路径或网络 URL
/// [videoFileName] 视频文件名（用于生成缩略图文件名）
/// [noteId] 笔记 ID，用于定位存储目录
///
/// 返回缩略图文件路径，失败返回 null。
Future<String?> generateThumbnail(String source, String videoFileName, String noteId) async {
  Player? player;
  try {
    player = Player();
    player.open(Media(source), play: false);

    // 等待 Player 就绪（监听 width stream，有值说明已加载）
    final completer = Completer<void>();
    final sub = player.stream.width.listen((w) {
      if (w != null && w > 0 && !completer.isCompleted) {
        completer.complete();
      }
    });
    // 超时保护：5 秒
    await completer.future.timeout(const Duration(seconds: 5));
    await sub.cancel();

    // 截取一帧
    final jpegBytes = await player.screenshot(format: 'image/jpeg');
    if (jpegBytes == null) return null;

    // 保存缩略图到视频同目录
    final appDir = await getApplicationDocumentsDirectory();
    final videoDir = Directory('${appDir.path}/videos/$noteId');
    if (!videoDir.existsSync()) {
      videoDir.createSync(recursive: true);
    }

    // 视频文件名 1718000000.mp4 → 缩略图 thumb_1718000000.jpg
    final baseName = videoFileName.replaceAll(RegExp(r'\.[^.]+$'), '');
    final thumbPath = '${videoDir.path}/thumb_$baseName.jpg';
    final file = File(thumbPath);
    await file.writeAsBytes(jpegBytes);

    return thumbPath;
  } catch (e) {
    debugPrint('generateThumbnail error: $e');
    return null;
  } finally {
    player?.dispose();
  }
}
```

需要在文件顶部添加 import：

```dart
import 'dart:async';
import 'package:media_kit/media_kit.dart';
import 'package:flutter/foundation.dart';
```

- [ ] **步骤 2：修改 deleteVideo 方法，联动删除缩略图**

将现有的 `deleteVideo` 方法替换为：

```dart
/// 删除单个视频文件及其缩略图
Future<void> deleteVideo(String filePath) async {
  final file = File(filePath);
  if (file.existsSync()) {
    await file.delete();
  }
  // 删除对应缩略图
  final thumbPath = _getThumbnailPath(filePath);
  if (thumbPath != null) {
    final thumbFile = File(thumbPath);
    if (thumbFile.existsSync()) {
      await thumbFile.delete();
    }
  }
}

/// 根据视频文件路径推导缩略图路径。
/// /videos/noteId/1718000000.mp4 → /videos/noteId/thumb_1718000000.jpg
/// 网络 URL 返回 null。
String? _getThumbnailPath(String videoPath) {
  if (videoPath.startsWith('http://') || videoPath.startsWith('https://')) {
    return null;
  }
  final dir = videoPath.substring(0, videoPath.lastIndexOf('/'));
  final fileName = videoPath.substring(videoPath.lastIndexOf('/') + 1);
  final baseName = fileName.replaceAll(RegExp(r'\.[^.]+$'), '');
  return '$dir/thumb_$baseName.jpg';
}
```

- [ ] **步骤 3：运行 flutter analyze 验证**

运行：`flutter analyze lib/services/video_storage_service.dart`
预期：无错误

- [ ] **步骤 4：Commit**

```bash
git add lib/services/video_storage_service.dart
git commit -m "feat: VideoStorageService 新增 generateThumbnail 方法和删除缩略图联动"
```

---

### 任务 2：修改 _insertVideo 和 _insertVideoUrl 调用截帧

**文件：**
- 修改：`lib/widgets/rich_text_editor.dart:530-565`

- [ ] **步骤 1：添加 VideoStorageService import**

在文件顶部的 import 区域，确认已有 `VideoStorageService` 的引入（搜索 `_videoService` 确认它已声明）。同时确认已有 `dart:convert` 引入。

- [ ] **步骤 2：修改 _insertVideo 方法，插入后生成缩略图**

将现有的 `_insertVideo` 方法（约 530-549 行）替换为：

```dart
Future<void> _insertVideo(Uint8List bytes, {String extension = 'mp4'}) async {
  final filePath = await _videoService.saveVideo(
    bytes,
    widget.noteId,
    extension: extension,
  );

  // 从文件路径提取文件名用于缩略图命名
  final fileName = filePath.split('/').last;

  // 异步生成缩略图（不阻塞 UI）
  String? thumbnail;
  try {
    thumbnail = await _videoService.generateThumbnail(filePath, fileName, widget.noteId);
  } catch (e) {
    debugPrint('Failed to generate video thumbnail: $e');
  }

  final videoData = jsonEncode({
    'source': filePath,
    'width': 400,
    if (thumbnail != null) 'thumbnail': thumbnail,
  });

  final index = _controller.selection.baseOffset;
  _controller.replaceText(
    index,
    0,
    BlockEmbed('video', videoData),
    null,
  );
}
```

- [ ] **步骤 3：修改 _insertVideoUrl 方法，插入后生成缩略图**

将现有的 `_insertVideoUrl` 方法（约 552-565 行）替换为：

```dart
/// 插入网络视频 URL
Future<void> _insertVideoUrl(String url) async {
  // 异步生成缩略图
  final uri = Uri.tryParse(url);
  final fileName = uri?.pathSegments.isNotEmpty == true
      ? uri!.pathSegments.last
      : DateTime.now().millisecondsSinceEpoch.toString();

  String? thumbnail;
  try {
    thumbnail = await _videoService.generateThumbnail(url, fileName, widget.noteId);
  } catch (e) {
    debugPrint('Failed to generate network video thumbnail: $e');
  }

  final videoData = jsonEncode({
    'source': url,
    'width': 400,
    if (thumbnail != null) 'thumbnail': thumbnail,
  });

  final index = _controller.selection.baseOffset;
  _controller.replaceText(
    index,
    0,
    BlockEmbed('video', videoData),
    null,
  );
}
```

- [ ] **步骤 4：运行 flutter analyze 验证**

运行：`flutter analyze lib/widgets/rich_text_editor.dart`
预期：无新增错误

- [ ] **步骤 5：Commit**

```bash
git add lib/widgets/rich_text_editor.dart
git commit -m "feat: 视频插入时自动生成缩略图"
```

---

### 任务 3：新增 _VideoThumbnailWidget 缩略图+播放按钮组件

**文件：**
- 修改：`lib/widgets/rich_text_editor.dart`（在 `_VideoEmbedBuilder` 之后、`_VideoPlayerWidget` 之前新增 widget）

- [ ] **步骤 1：在 _VideoEmbedBuilder 和 _VideoPlayerWidget 之间新增组件**

在 `_VideoEmbedBuilder` 类的结束 `}` 之后（约 2043 行），`_VideoPlayerWidget` 类定义之前，插入：

```dart
/// 视频缩略图展示组件：显示缩略图 + 播放按钮，点击后切换为播放器。
class _VideoThumbnailWidget extends StatefulWidget {
  final String thumbnailPath;
  final String source;
  final VoidCallback? onDelete;

  const _VideoThumbnailWidget({
    required this.thumbnailPath,
    required this.source,
    this.onDelete,
  });

  @override
  State<_VideoThumbnailWidget> createState() => _VideoThumbnailWidgetState();
}

class _VideoThumbnailWidgetState extends State<_VideoThumbnailWidget> {
  bool _showPlayer = false;

  void _showContextMenu(TapDownDetails details) {
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        details.globalPosition.dx,
        details.globalPosition.dy,
        details.globalPosition.dx + 1,
        details.globalPosition.dy + 1,
      ),
      items: [
        PopupMenuItem(
          value: 'delete',
          child: Text('删除视频', style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ),
      ],
    ).then((value) {
      if (value == 'delete' && mounted) {
        widget.onDelete?.call();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_showPlayer) {
      return _VideoPlayerWidget(
        source: widget.source,
        onDelete: widget.onDelete,
      );
    }

    final isNetwork = widget.thumbnailPath.startsWith('http://') ||
        widget.thumbnailPath.startsWith('https://');
    final image = isNetwork
        ? Image.network(widget.thumbnailPath, fit: BoxFit.cover)
        : Image.file(File(widget.thumbnailPath), fit: BoxFit.cover);

    return GestureDetector(
      onTap: () => setState(() => _showPlayer = true),
      child: Listener(
        onPointerDown: (event) {
          if (event.kind == PointerDeviceKind.mouse &&
              event.buttons == kSecondaryMouseButton) {
            _showContextMenu(TapDownDetails(
              globalPosition: event.position,
              localPosition: event.localPosition,
            ));
          }
        },
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400, maxHeight: 300),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: image,
                ),
              ),
              // 半透明播放按钮
              Container(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.4),
                  shape: BoxShape.circle,
                ),
                padding: const EdgeInsets.all(12),
                child: const Icon(
                  Icons.play_arrow,
                  color: Colors.white,
                  size: 36,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

确保文件顶部有 `import 'dart:io';`（用于 `File`）。

- [ ] **步骤 2：运行 flutter analyze 验证**

运行：`flutter analyze lib/widgets/rich_text_editor.dart`
预期：无新增错误

- [ ] **步骤 3：Commit**

```bash
git add lib/widgets/rich_text_editor.dart
git commit -m "feat: 新增 _VideoThumbnailWidget 缩略图+播放按钮组件"
```

---

### 任务 4：修改 _VideoEmbedBuilder 优先使用缩略图

**文件：**
- 修改：`lib/widgets/rich_text_editor.dart`（`_VideoEmbedBuilder.build` 方法，约 2022-2042 行）

- [ ] **步骤 1：替换 _VideoEmbedBuilder.build 方法**

将现有的 `build` 方法替换为：

```dart
@override
Widget build(BuildContext context, EmbedContext embedContext) {
  final rawData = embedContext.node.value.data as String;

  String source;
  String? thumbnail;
  try {
    final json = jsonDecode(rawData) as Map<String, dynamic>;
    source = json['source'] as String;
    thumbnail = json['thumbnail'] as String?;
  } catch (_) {
    source = rawData;
  }

  final onDelete = () {
    final offset = embedContext.node.documentOffset;
    if (offset >= 0) {
      controller.replaceText(offset, 1, '', null);
    }
  };

  // 有缩略图：先显示缩略图+播放按钮
  if (thumbnail != null) {
    return _VideoThumbnailWidget(
      thumbnailPath: thumbnail,
      source: source,
      onDelete: onDelete,
    );
  }

  // 无缩略图（旧数据）：保持播放器模式
  return _VideoPlayerWidget(
    source: source,
    onDelete: onDelete,
  );
}
```

- [ ] **步骤 2：运行 flutter analyze 验证**

运行：`flutter analyze lib/widgets/rich_text_editor.dart`
预期：无新增错误

- [ ] **步骤 3：Commit**

```bash
git add lib/widgets/rich_text_editor.dart
git commit -m "feat: 编辑器视频优先显示缩略图，点击后播放"
```

---

### 任务 5：扩展 MediaInfo 支持缩略图，更新列表显示

**文件：**
- 修改：`lib/utils/media_thumbnail.dart`
- 修改：`lib/screens/home_screen.dart`

- [ ] **步骤 1：扩展 MediaInfo 类增加 thumbnail 字段**

在 `media_thumbnail.dart` 中修改 `MediaInfo` 类：

```dart
class MediaInfo {
  final String source;
  final bool isVideo;
  final String? thumbnail;

  const MediaInfo({required this.source, required this.isVideo, this.thumbnail});

  bool get isNetwork =>
      source.startsWith('http://') || source.startsWith('https://');
}
```

- [ ] **步骤 2：修改 extractFirstMedia 提取 thumbnail 字段**

在 `media_thumbnail.dart` 中，修改视频部分（约 33-40 行），提取 thumbnail：

```dart
      // 检查视频
      final video = insert['video'];
      if (video is String) {
        final result = _parseVideoData(video);
        if (result != null) {
          return result;
        }
      }
```

替换 `_parseSource` 为两个方法：

```dart
/// 解析图片数据（无 thumbnail 字段）
String? _parseSource(String rawData) {
  try {
    final json = jsonDecode(rawData) as Map<String, dynamic>;
    return json['source'] as String?;
  } catch (_) {
    return rawData.isNotEmpty ? rawData : null;
  }
}

/// 解析视频数据（含 thumbnail 字段）
MediaInfo? _parseVideoData(String rawData) {
  try {
    final json = jsonDecode(rawData) as Map<String, dynamic>;
    final source = json['source'] as String?;
    if (source == null) return null;
    return MediaInfo(
      source: source,
      isVideo: true,
      thumbnail: json['thumbnail'] as String?,
    );
  } catch (_) {
    if (rawData.isNotEmpty) {
      return MediaInfo(source: rawData, isVideo: true);
    }
    return null;
  }
}
```

同时修改图片部分，使用 `MediaInfo`：

```dart
      // 检查图片
      final image = insert['image'];
      if (image is String) {
        final source = _parseSource(image);
        if (source != null) {
          return MediaInfo(source: source, isVideo: false);
        }
      }
```

- [ ] **步骤 3：修改 home_screen.dart 的 _buildListThumbnail，优先使用 thumbnail**

在 `_buildListThumbnail` 方法中，视频部分改为优先使用 `media.thumbnail`：

```dart
Widget _buildListThumbnail(MediaInfo media) {
  // 视频有缩略图时直接显示
  if (media.isVideo && media.thumbnail != null) {
    final isNet = media.thumbnail!.startsWith('http://') ||
        media.thumbnail!.startsWith('https://');
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: 48,
        height: 48,
        child: isNet
            ? Image.network(media.thumbnail!, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Icon(Icons.play_circle_filled, size: 24))
            : Image.file(File(media.thumbnail!), fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Icon(Icons.play_circle_filled, size: 24)),
      ),
    );
  }

  return ClipRRect(
    borderRadius: BorderRadius.circular(6),
    child: SizedBox(
      width: 48,
      height: 48,
      child: media.isVideo
          ? Container(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: const Center(
                child: Icon(Icons.play_circle_filled, size: 24),
              ),
            )
          : media.isNetwork
              ? Image.network(media.source, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Icon(Icons.broken_image))
              : Image.file(File(media.source), fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Icon(Icons.broken_image)),
    ),
  );
}
```

- [ ] **步骤 4：修改 home_screen.dart 的 _buildWaterfallThumbnail，优先使用 thumbnail**

```dart
Widget _buildWaterfallThumbnail(MediaInfo media) {
  // 视频有缩略图时直接显示
  if (media.isVideo && media.thumbnail != null) {
    final isNet = media.thumbnail!.startsWith('http://') ||
        media.thumbnail!.startsWith('https://');
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 120),
        child: Stack(
          alignment: Alignment.center,
          children: [
            isNet
                ? Image.network(media.thumbnail!, fit: BoxFit.cover, width: double.infinity,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink())
                : Image.file(File(media.thumbnail!), fit: BoxFit.cover, width: double.infinity,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink()),
            // 播放图标叠加
            Container(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.3),
                shape: BoxShape.circle,
              ),
              padding: const EdgeInsets.all(8),
              child: const Icon(Icons.play_arrow, color: Colors.white, size: 20),
            ),
          ],
        ),
      ),
    );
  }

  return ClipRRect(
    borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 120),
      child: media.isVideo
          ? Container(
              height: 80,
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: const Center(
                child: Icon(Icons.play_circle_filled, size: 36),
              ),
            )
          : media.isNetwork
              ? Image.network(media.source, fit: BoxFit.cover, width: double.infinity,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink())
              : Image.file(File(media.source), fit: BoxFit.cover, width: double.infinity,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink()),
    ),
  );
}
```

- [ ] **步骤 5：运行 flutter analyze 验证**

运行：`flutter analyze`
预期：无新增错误

- [ ] **步骤 6：Commit**

```bash
git add lib/utils/media_thumbnail.dart lib/screens/home_screen.dart
git commit -m "feat: 列表和瀑布流视图优先显示视频缩略图"
```

---

### 任务 6：整体验证

- [ ] **步骤 1：运行 flutter analyze**

运行：`flutter analyze`
预期：无新增错误（已有的 info 级别可忽略）

- [ ] **步骤 2：手动验证**

运行 `flutter run -d windows`，测试以下场景：
1. 插入本地视频 → 编辑器显示缩略图+播放按钮，列表显示缩略图
2. 点击播放按钮 → 切换为视频播放器
3. 关闭视频笔记后重新打开 → 缩略图即时显示
4. 插入不含缩略图的旧视频数据 → 保持播放器模式（向后兼容）
5. 删除含缩略图的视频 → 缩略图文件一同被删除

- [ ] **步骤 3：最终 Commit**

```bash
git add -A
git commit -m "feat: 视频缩略图预生成功能完成"
```
