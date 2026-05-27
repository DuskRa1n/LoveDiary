part of '../../app.dart';

class _OneDriveConfigFormData {
  const _OneDriveConfigFormData({
    required this.remoteFolder,
    required this.syncOnWrite,
    required this.minimumSyncIntervalMinutes,
    required this.maxDestructiveActions,
  });

  final String remoteFolder;
  final bool syncOnWrite;
  final int minimumSyncIntervalMinutes;
  final int maxDestructiveActions;
}

class _OneDriveSyncSettingsPage extends StatefulWidget {
  const _OneDriveSyncSettingsPage({
    required this.defaults,
    required this.onDisconnect,
  });

  final _OneDriveConfigFormData defaults;
  final Future<bool> Function() onDisconnect;

  @override
  State<_OneDriveSyncSettingsPage> createState() =>
      _OneDriveSyncSettingsPageState();
}

class _OneDriveSyncSettingsPageState extends State<_OneDriveSyncSettingsPage> {
  late final TextEditingController _remoteFolderController;
  late final TextEditingController _minimumIntervalController;
  late final TextEditingController _maxDestructiveActionsController;
  late bool _syncOnWrite;

  @override
  void initState() {
    super.initState();
    _remoteFolderController = TextEditingController(
      text: widget.defaults.remoteFolder,
    );
    _minimumIntervalController = TextEditingController(
      text: widget.defaults.minimumSyncIntervalMinutes.toString(),
    );
    _maxDestructiveActionsController = TextEditingController(
      text: widget.defaults.maxDestructiveActions.toString(),
    );
    _syncOnWrite = widget.defaults.syncOnWrite;
  }

  @override
  void dispose() {
    _remoteFolderController.dispose();
    _minimumIntervalController.dispose();
    _maxDestructiveActionsController.dispose();
    super.dispose();
  }

  Future<void> _disconnect() async {
    final disconnected = await widget.onDisconnect();
    if (disconnected && mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('OneDrive 设置'),
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close_rounded),
        ),
      ),
      body: DiaryPage(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const DiaryCompactHeader(eyebrow: '同步设置', title: '控制 OneDrive 同步'),
            const SizedBox(height: 20),
            DiaryPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _remoteFolderController,
                    decoration: const InputDecoration(
                      labelText: '远端目录',
                      hintText: '默认 love_diary',
                    ),
                  ),
                  const SizedBox(height: 18),
                  SwitchListTile(
                    value: _syncOnWrite,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('写入后自动同步'),
                    onChanged: (value) {
                      setState(() {
                        _syncOnWrite = value;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _minimumIntervalController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '自动同步最小间隔（分钟）',
                      hintText: '默认 0，表示每次写入都同步',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _maxDestructiveActionsController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '删除保护阈值',
                      hintText: '默认 3',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton(
                  onPressed: () {
                    final remoteFolder =
                        _remoteFolderController.text.trim().isEmpty
                        ? 'love_diary'
                        : _remoteFolderController.text.trim();
                    final minimumInterval =
                        int.tryParse(_minimumIntervalController.text.trim()) ??
                        10;
                    final maxDestructiveActions =
                        int.tryParse(
                          _maxDestructiveActionsController.text.trim(),
                        ) ??
                        3;
                    Navigator.of(context).pop(
                      _OneDriveConfigFormData(
                        remoteFolder: remoteFolder,
                        syncOnWrite: _syncOnWrite,
                        minimumSyncIntervalMinutes: minimumInterval < 1
                            ? 1
                            : minimumInterval,
                        maxDestructiveActions: maxDestructiveActions < 0
                            ? 0
                            : maxDestructiveActions,
                      ),
                    );
                  },
                  child: const Text('保存'),
                ),
                OutlinedButton.icon(
                  onPressed: _disconnect,
                  icon: const Icon(Icons.link_off_rounded),
                  label: const Text('断开连接'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
