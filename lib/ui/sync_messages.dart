import 'dart:math';

const List<String> kSyncWaitingMessages = [
  '正在把刚刚发生的事情好好收起来。',
  '正在整理云端记忆，先别急着离开。',
  '正在把本机和云端对齐，稍等一下。',
  '正在确认每一篇日记都放在正确的位置。',
  '正在把新的记录送到云端备份。',
  '正在检查两边的数据，避免漏掉任何一篇。',
  '正在安静同步，完成前先把应用留在这里。',
  '正在把今天的内容妥善保存。',
  '正在整理附件和日记，请稍等。',
  '正在同步数据，保持网络稳定会更快一点。',
  '正在把最近的变化写进云端。',
  '正在确认删除、修改和新增记录。',
];

String randomSyncWaitingMessage() {
  return kSyncWaitingMessages[Random().nextInt(kSyncWaitingMessages.length)];
}
