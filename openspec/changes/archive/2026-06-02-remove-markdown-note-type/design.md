## Context

项目有两种编辑器：富文本编辑器（flutter_quill）和独立的 Markdown 编辑器（flutter_markdown）。富文本编辑器已内置 Markdown 语法自动转换功能（`MarkdownAutoConverter`），独立 Markdown 编辑器不再有价值。

## Goals / Non-Goals

**Goals:**
- 移除独立的 Markdown 编辑器组件和相关依赖
- 简化笔记创建流程，去掉类型选择步骤
- 所有笔记统一为富文本类型

**Non-Goals:**
- 不移除富文本编辑器中的 Markdown 自动转换功能
- 不迁移已有的 Markdown 类型笔记数据（现有 markdown 类型笔记的 content 字段为纯文本，打开时由富文本编辑器以纯文本显示）

## Decisions

### 1. 笔记类型字段保留但默认固定为 rich_text

**选择**: 保留 `Note.type` 字段但不再暴露类型选择，所有新笔记固定 `'rich_text'`。

**理由**: 已有数据库中存在 `type` 字段，删除字段需要数据库迁移。保留字段但固定值更安全，且未来可扩展。

### 2. 新建笔记直接创建，不弹选择框

**选择**: FloatingActionButton 点击后直接创建富文本笔记，不再弹出 BottomSheet 选择类型。

**理由**: 只有一种类型时弹选择框是多余的。

## Risks / Trade-offs

- **[兼容性] 已有 markdown 类型笔记** → 保留 type 字段，打开时富文本编辑器以纯文本显示内容（可编辑），不做数据迁移
- **[依赖] flutter_markdown 移除后不可逆** → 该包仅被 markdown_editor.dart 使用，移除安全
