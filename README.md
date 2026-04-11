# 恋爱日记

一个给两个人长期一起用的 Flutter 日记 app。  
重点不是“发圈”或者“社交”，而是把每天的记录、图片、评论和同步先做扎实。

## 现在能做什么

- 写、改、删日记
- 给日记加图片和评论
- 按时间线浏览，支持关键词、心情、日期筛选
- 删除后先进回收站，7 天后再彻底清理
- 用坚果云 WebDAV 同步
- 本地空库时，可以先从坚果云恢复
- 同步冲突时，可以手动选保留本地还是采用云端

## 现在的定位

这是一个本地优先项目。

- 本地文件是真源
- 坚果云只是同步层，不是后端数据库
- 目前主要面向 Android 自用和内测

## 目录结构

核心代码都在 `lib/`：

- `lib/app.dart`
  目前的应用壳和若干页面入口
- `lib/data/`
  本地文件存储、回收站、草稿、同步状态
- `lib/models/`
  日记、资料、附件等数据模型
- `lib/sync/`
  同步计划、执行器、WebDAV 远端实现
- `lib/ui/`
  主页、时间线、“我们”页和同步冲突页

本地数据结构大致是：

```text
profile.json
entries/
attachments/
drafts/
sync/
cache/
dustbin/
```

## 本地运行

先装 Flutter 和 Android SDK，然后在项目根目录执行：

```powershell
flutter pub get
flutter run
```

## 测试

```powershell
flutter test
```

如果你本机 Flutter 工具链有问题，测试可能会超时或者起不来，这个项目之前就碰到过这种情况。

## Android 打包

真机：

```powershell
flutter build apk --release --target-platform android-arm64
```

模拟器：

```powershell
flutter build apk --release --target-platform android-x64
```

平时调试：

```powershell
flutter build apk --debug
```

## 坚果云同步怎么配

应用里要填这几个值：

- WebDAV 地址
- 坚果云账号
- 第三方应用密码
- 远端目录

常见地址：

```text
https://dav.jianguoyun.com/dav/
```

注意：

- 不要把真实账号和应用密码提交到仓库
- 调试自动注入默认是关闭的
- 如果你只想自己本地偷懒，可以改 `lib/sync/webdav/jianguoyun_debug_bootstrap.dart`
- 这种改动不要再 push

## 现在已知的现实情况

- 这个项目已经偏离 Flutter 模板项目很多了，但 `app.dart` 还比较大
- UI 已经做过一轮重构，但还有继续拆页的空间
- 坚果云同步能用，但还可以继续补更细的冲突处理和同步记录页
- 目前主要是 Android 路线，iOS 还没认真收

## 如果你是来继续改这个项目

建议优先看这几个文件：

- `lib/app.dart`
- `lib/data/diary_storage.dart`
- `lib/sync/diary_sync_executor.dart`
- `lib/sync/webdav/webdav_remote_source.dart`
- `lib/ui/real_today_tab.dart`
- `lib/ui/real_timeline_tab.dart`
- `lib/ui/real_us_tab.dart`

## 仓库里的素材

项目相关图放在 `figs/`。

- 当前保留的是 app logo 源图
- 临时截图、测试图、带个人信息的图不要再往这里堆
