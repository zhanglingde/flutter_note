## ADDED Requirements

### Requirement: 缩略图生成方法
`VideoStorageService` SHALL 提供 `generateThumbnail(String source, String noteId, {int seekMs = 0})` 方法，使用 media_kit Player 的 screenshot API 从视频中截取 JPEG 帧。方法 SHALL 返回缩略图文件的绝对路径，失败时返回 null。

#### Scenario: 本地视频缩略图生成成功
- **WHEN** 调用 `generateThumbnail` 传入有效的本地视频文件路径和 noteId
- **THEN** 创建临时 Player 打开视频（不自动播放），调用 screenshot 获取 JPEG bytes，保存为 `thumb_{timestamp}.jpg`，返回缩略图绝对路径

#### Scenario: 缩略图生成失败
- **WHEN** 视频文件损坏或 Player 初始化失败
- **THEN** 方法返回 null，不抛出异常，不产生临时文件残留

#### Scenario: 截帧后资源释放
- **WHEN** 截帧完成（无论成功或失败）
- **THEN** 临时 Player 及 VideoController 被 dispose，无资源泄漏

### Requirement: 缩略图文件存储规范
缩略图 SHALL 存储在与视频相同的目录 `{appDir}/videos/{noteId}/` 下，文件名 SHALL 为 `thumb_{视频文件名}.jpg`（视频文件名不含扩展名时直接加 `thumb_` 前缀）。

#### Scenario: 缩略图文件命名
- **WHEN** 视频文件为 `1718000000.mp4`
- **THEN** 缩略图文件命名为 `thumb_1718000000.jpg`，存储在同一目录

#### Scenario: 缩略图目录不存在时自动创建
- **WHEN** `videos/{noteId}/` 目录不存在
- **THEN** 自动创建目录后再保存缩略图

### Requirement: 缩略图删除联动
删除单个视频文件时 SHALL 同时删除对应的缩略图文件。缩略图路径 SHALL 通过视频文件路径推导：同目录下 `thumb_{文件名去扩展名}.jpg`。

#### Scenario: 删除视频时同时删除缩略图
- **WHEN** 调用 `VideoStorageService.deleteVideo("/path/to/1718000000.mp4")`
- **THEN** 视频文件和 `thumb_1718000000.jpg` 缩略图都被删除

#### Scenario: 缩略图文件不存在时静默处理
- **WHEN** 删除视频时对应的缩略图文件不存在
- **THEN** 仅删除视频文件，不抛出异常

### Requirement: Web 平台跳过缩略图生成
Web 平台 SHALL 跳过缩略图生成流程（media_kit screenshot API 在 Web 不可用），直接返回 null。

#### Scenario: Web 平台调用 generateThumbnail
- **WHEN** 在 Web 平台调用 `generateThumbnail`
- **THEN** 直接返回 null，不创建 Player
