## Context

当前富文本编辑器使用 `flutter_quill` 包，用户通过工具栏按钮进行格式化。许多用户习惯 Markdown 语法，希望能够直接输入 Markdown 并自动转换为富文本格式。

**约束条件**:
- 必须与现有 Quill 编辑器兼容
- 不能破坏撤销/重做功能
- 需要支持中文等复合输入法
- 转换应该是可选的（用户可以关闭）

**技术背景**:
- Quill 使用 Delta 格式表示文档
- 需要监听文本变化并检测 Markdown 模式
- 转换需要生成正确的 Delta 操作

## Goals / Non-Goals

**Goals:**
- 实现行内 Markdown 语法的自动检测和转换
- 支持常见 Markdown 语法（标题、粗体、斜体、删除线、代码、列表、引用）
- 提供用户可控的开关
- 保持撤销/重做功能正常工作
- 兼容复合输入法

**Non-Goals:**
- 不支持多行 Markdown 语法（如代码块、表格）
- 不支持链接和图片的 Markdown 语法（首版不包含）
- 不提供 Markdown 到富文本的批量导入功能
- 不提供富文本到 Markdown 的导出功能

## Decisions

### 1. 实现方式：文本监听器 + 正则匹配

**决策**: 使用 Quill 控制器的文本监听器，结合正则表达式检测 Markdown 模式

**理由**:
- flutter_quill 没有内置 Markdown 自动转换功能
- 正则表达式足够处理简单的行内 Markdown 语法
- 可以精确控制触发时机（空格或回车）

**替代方案考虑**:
- 使用第三方包（如 `flutter_quill_extensions`）：功能有限，不完全符合需求
- 预处理输入：会破坏撤销/重做历史

### 2. 触发时机：空格和回车键

**决策**: 当用户输入空格或回车时检测并转换 Markdown 语法

**理由**:
- 符合用户习惯（大多数 Markdown 编辑器如此工作）
- 避免输入过程中的误转换
- 提供明确的"提交"信号

**转换规则**:
| 语法 | 触发 | 示例 |
|------|------|------|
| 标题 | 行首 + 空格 | `# 标题` → H1 |
| 粗体 | 尾部 `**` + 内容 | `**文本**` → **文本** |
| 斜体 | 尾部 `*` + 内容 | `*文本*` → *文本* |
| 列表 | 行首 + 空格 | `- 项目` → 列表项 |

### 3. 架构设计：独立的转换器类

**决策**: 创建独立的 `MarkdownAutoConverter` 类

```dart
class MarkdownAutoConverter {
  final QuillController controller;

  // 检测并转换当前行
  void processCurrentLine();

  // 检测行内语法（粗体、斜体等）
  void processInlineMarkdown();

  // 正则模式定义
  static final Map<String, RegExp> patterns = {...};
}
```

**理由**:
- 关注点分离，易于测试
- 可以独立启用/禁用
- 方便扩展新的 Markdown 语法

### 4. 状态管理：使用 Quill Delta 操作

**决策**: 转换时生成 Delta 操作而不是直接修改文本

**理由**:
- 保持撤销/重做历史完整
- 符合 Quill 的操作模型
- 更精确的位置控制

**实现示例**:
```dart
void _applyConversion(TextRange range, Map<String, dynamic> attributes) {
  final delta = Delta()
    ..retain(range.start)
    ..delete(range.length)
    ..insert(range.textInside(controller.document.toPlainText()), attributes);
  controller.document.compose(delta, ChangeSource.local);
}
```

### 5. 设置存储：SharedPreferences

**决策**: 使用 SharedPreferences 存储 Markdown 自动转换开关状态

**理由**:
- 简单的布尔值存储
- 已有依赖（项目已使用）
- 跨平台支持

## Risks / Trade-offs

### Risk 1: 复合输入法兼容性
**风险**: 中文输入法在输入过程中会产生额外的文本变化事件
**缓解措施**:
- 使用 `TextEditingValue.composing` 检测复合输入状态
- 仅在复合输入完成后触发转换
- 添加输入法测试用例

### Risk 2: 撤销历史混乱
**风险**: 转换操作可能导致撤销历史不直观
**缓解措施**:
- 使用单一 Delta 操作完成转换
- 考虑将原始输入和转换合并为一个操作
- 用户测试验证

### Risk 3: 性能影响
**风险**: 每次输入都检测可能影响性能
**缓解措施**:
- 仅检测当前行而非全文
- 使用编译后的正则表达式
- 添加防抖（debounce）机制

### Trade-off 1: 不支持所有 Markdown 语法
**权衡**: 首版仅支持行内语法，不支持代码块、表格等
**影响**: 用户仍需使用工具栏插入复杂元素

### Trade-off 2: 转换不可逆
**权衡**: 转换后无法自动还原为 Markdown 源文本
**影响**: 用户需要使用撤销来回退转换

## Migration Plan

**阶段 1: 核心实现** (1-2 天)
- 实现 `MarkdownAutoConverter` 类
- 添加基本语法模式（标题、粗体、斜体）
- 集成到 RichTextEditor

**阶段 2: 完善功能** (1 天)
- 添加剩余语法支持（删除线、代码、列表、引用）
- 添加工具栏开关
- 实现设置持久化

**阶段 3: 测试和优化** (1 天)
- 单元测试
- 输入法兼容性测试
- 性能优化

**回滚策略**:
- 功能可通过开关完全禁用
- 删除转换器代码不影响其他功能
- 设置项有默认值

## Open Questions

1. **默认启用还是禁用？**
   - 建议：默认启用，因为熟悉 Markdown 的用户会期望这个功能

2. **是否需要转换提示？**
   - 建议：首版不添加，保持简洁。如果用户反馈需要，再添加视觉反馈

3. **是否支持自定义语法？**
   - 建议：首版不支持，保持简单。未来可考虑添加配置
