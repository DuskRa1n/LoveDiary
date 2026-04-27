# 恋爱日记

一个给两个人长期一起用的日记 app。  

## 现在能做什么

- 写、改、删日记
- 给日记加图片和评论
- 按时间线浏览，支持关键词、心情、日期筛选
- 用 OneDrive 同步

## 目录结构

核心代码都在 `lib/`：

- `lib/app.dart`
  目前的应用壳和若干页面入口
- `lib/data/`
  本地文件存储、回收站、草稿、同步状态
- `lib/models/`
  日记、资料、附件等数据模型
- `lib/sync/`
  同步计划、执行器、OneDrive 远端实现
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
