# LoveDiary

LoveDiary 是一个为两个人长期共同记录生活设计的情侣日记 App。它把日记、评论、图片、纪念日和行程安排放在同一个温柔的时间轴里，并通过 OneDrive 在多台设备之间同步。

当前发布重点是 Android，正式包名为 `com.ericchen.lovediary`，当前版本为 `1.2.12+66`。

## 主要功能

- 记录日记：支持新建、编辑、删除、评论和心情标记。
- 图片附件：支持压缩导入或保留原图，新导入的预览图会优先使用 JPEG 压缩以减少同步体积。
- 时间线浏览：按日期展示日记，支持搜索、心情筛选和日期筛选。
- 今日页：展示相伴天数、最近心情、当月日记热力图和近期重要日子。
- 日程管理：支持单次行程计划和每年重复纪念日，日程会参与 OneDrive 同步。
- 回收站：删除的日记会先进入回收站，支持恢复或彻底删除。
- 草稿保护：新建日记支持自动草稿保存，减少编辑中断造成的内容丢失。
- OneDrive 同步：支持手动同步、写入后自动同步、前台通知进度、冲突处理和启动恢复。

## 同步策略

LoveDiary 目前只保留 OneDrive 同步，不再包含 WebDAV / 坚果云入口。

同步逻辑使用稳定的 OneDrive item id 维护远端节点基线，避免依赖不可靠的路径还原。同步执行过程中会写入本地 checkpoint，如果网络中断、App 被杀或前台服务中断，下一次同步会禁用旧的增量基线并做安全刷新，避免用过期状态继续规划上传、下载或删除。

为保护本地文件，远端路径会经过白名单和目录边界校验，只允许同步业务文件：

```text
profile.json
schedules.json
entries/
attachments/
```

以下本机状态不会进入云端同步：

```text
local_settings.json
drafts/
sync/
cache/
dustbin/
```

OneDrive access token 和 refresh token 使用平台安全存储；日记正文、评论、资料、日程和附件按当前产品取舍保留为本地文件，并进入 OneDrive 同步范围。

## 项目结构

核心代码在 `lib/`：

```text
lib/
  app.dart                         # App 入口、主 Shell、同步编排
  data/                            # 本地文件存储、草稿、回收站、同步状态
  models/                          # 日记、资料、附件、日程模型
  sync/                            # 同步计划、执行器、OneDrive 实现
  ui/
    attachments/                   # 附件网格、图片加载、预览页
    dustbin/                       # 回收站页
    entries/                       # 日记详情、新建/编辑、评论卡片
    profile/                       # 首次设置和资料编辑
    schedules/                     # 日程列表、编辑页、日期选择
    settings/                      # OneDrive 同步设置
    shell/                         # 底部导航、浮动操作、页面容器
    real_today_tab.dart            # 今日页
    real_timeline_tab.dart         # 回忆时间线
    real_us_tab.dart               # 我们页
    sync_conflict_page.dart        # 同步冲突处理
```

Android 相关配置在 `android/`，包括正式应用 ID、release signing 配置读取、前台同步服务和原生 JPEG 压缩通道。

## 本地数据结构

App 数据大致按下面的结构存放在应用私有目录：

```text
profile.json
schedules.json
entries/
attachments/
drafts/
sync/
cache/
dustbin/
local_settings.json
```

其中 `entries/`、`attachments/`、`profile.json`、`schedules.json` 是正式同步数据；`drafts/`、`sync/`、`cache/`、`dustbin/`、`local_settings.json` 属于本机运行状态。

## 开发与验证

安装依赖：

```powershell
D:\Software\flutter\bin\flutter.bat pub get
```

静态检查：

```powershell
D:\Software\flutter\bin\flutter.bat analyze
```

运行测试：

```powershell
D:\Software\flutter\bin\flutter.bat test
```

构建 Android arm64 release APK：

```powershell
D:\Software\flutter\bin\flutter.bat build apk --release --target-platform android-arm64 --split-per-abi
```

构建产物位置：

```text
build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

## 发布备注

- Android applicationId / namespace：`com.ericchen.lovediary`
- OneDrive clientId：`add98f89-728e-4e08-9c71-13a546b951bc`
- Android redirect URI 需要与正式包名和签名哈希匹配。
- release 构建需要本地配置 `android/key.properties` 和对应 keystore，仓库只保留 `android/key.properties.example`。

## 当前状态

最近一次完整验证：

- `flutter analyze`
- `flutter test`
- `flutter build apk --release --target-platform android-arm64 --split-per-abi`
