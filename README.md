# 恋爱日记 LoveDiary

一款本地优先的 Flutter 恋爱日记应用，面向两个人长期记录、浏览和同步共同回忆。

## 当前能力

- 写日记、编辑日记、删除日记
- 图片导入、预览、缩略图展示
- 评论、时间线浏览、搜索与基础筛选
- 回收站保留与恢复
- 坚果云 WebDAV 同步
- 首次空库时从坚果云恢复
- 同步冲突处理页

## 存储设计

应用使用本地文件作为真源，主要目录结构如下：

```text
profile.json
entries/
attachments/
drafts/
sync/
cache/
dustbin/
```

其中：

- `entries/` 保存正式日记
- `attachments/` 保存正式图片附件
- `drafts/` 保存草稿及草稿附件
- `sync/` 保存同步状态和 tombstone
- `dustbin/` 保存延迟删除的内容

## 同步方案

当前主线同步方案为坚果云 WebDAV。

需要配置：

- WebDAV 地址
- 坚果云账号
- 第三方应用密码
- 远端目录

调试引导默认关闭，不会在仓库里保存任何真实账号或密码。

## 开发环境

- Flutter 3.x
- Dart 3.x
- Android Studio / Android SDK

常用命令：

```powershell
flutter pub get
flutter run
flutter test
flutter build apk --release --target-platform android-arm64
flutter build apk --release --target-platform android-x64
```

## Android 打包

真机推荐：

```powershell
flutter build apk --release --target-platform android-arm64
```

模拟器推荐：

```powershell
flutter build apk --release --target-platform android-x64
```

## 仓库说明

当前仓库已经移除了内测用的明文同步凭证。

如果你要本地启用调试自动注入，请只在自己机器上修改：

- `lib/sync/webdav/jianguoyun_debug_bootstrap.dart`

不要把真实账号、应用密码或个人同步目录再次提交到仓库。
