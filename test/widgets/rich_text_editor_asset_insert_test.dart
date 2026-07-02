import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:note/services/note_storage_service.dart';
import 'package:note/services/sync/asset_repository.dart';
import 'package:note/widgets/rich_text_editor.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('RichTextEditor accepts assetRepository and storageService parameters',
      () async {
    final tmpDir = await Directory.systemTemp.createTemp('editor_test_');
    final storage = NoteStorageService()
      ..dbPathOverride = '${tmpDir.path}/test.db'
      ..appDocumentsDirOverride = '${tmpDir.path}/appdocs';
    await storage.init();
    final repo = AssetRepository(storage);
    addTearDown(() async {
      await storage.close();
      if (tmpDir.existsSync()) await tmpDir.delete(recursive: true);
    });

    // 目的：验证 RichTextEditor 构造函数能接受新增的 assetRepository /
    // storageService 可选参数（任务 6 的核心契约）。
    //
    // 不进入完整渲染（pumpWidget）：富文本编辑器（Quill + media_kit）在 widget
    // 测试环境初始化成本极高，且本任务只关心"构造注入是否成立"。任务 13 的端到端
    // 集成测试会覆盖完整渲染流程。
    expect(
      () => RichTextEditor(
        key: const ValueKey('editor'),
        noteId: 'n1',
        initialContent: '',
        storageService: storage,
        assetRepository: repo,
        onContentChanged: (_) {},
      ),
      returnsNormally,
    );
  });

  test('RichTextEditor works without assetRepository (legacy mode)', () async {
    expect(
      () => RichTextEditor(
        key: const ValueKey('editor-legacy'),
        noteId: 'n2',
        initialContent: '',
        onContentChanged: (_) {},
      ),
      returnsNormally,
    );
  });
}
