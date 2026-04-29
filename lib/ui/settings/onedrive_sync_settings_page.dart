part of '../../app.dart';

class _OneDriveConfigFormData {
  const _OneDriveConfigFormData({
    required this.remoteFolder,
    required this.syncOnWrite,
    required this.minimumSyncIntervalMinutes,
    required this.maxDestructiveActions,
    required this.syncOriginals,
    required this.downloadOriginals,
    required this.localOriginalRetentionDays,
  });

  final String remoteFolder;
  final bool syncOnWrite;
  final int minimumSyncIntervalMinutes;
  final int maxDestructiveActions;
  final bool syncOriginals;
  final bool downloadOriginals;
  final int localOriginalRetentionDays;
}

class _OneDriveSyncSettingsPage extends StatefulWidget {
  const _OneDriveSyncSettingsPage({
    required this.defaults,
    required this.onDisconnect,
    required this.onCleanLocalOriginals,
  });

  final _OneDriveConfigFormData defaults;
  final Future<bool> Function() onDisconnect;
  final Future<ImageCleanupResult> Function(Duration olderThan)
  onCleanLocalOriginals;

  @override
  State<_OneDriveSyncSettingsPage> createState() =>
      _OneDriveSyncSettingsPageState();
}

class _OneDriveSyncSettingsPageState extends State<_OneDriveSyncSettingsPage> {
  late final TextEditingController _remoteFolderController;
  late final TextEditingController _minimumIntervalController;
  late final TextEditingController _maxDestructiveActionsController;
  late final TextEditingController _localOriginalRetentionController;
  late bool _syncOnWrite;
  late bool _syncOriginals;
  late bool _downloadOriginals;
  bool _isCleaningOriginals = false;

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
    _localOriginalRetentionController = TextEditingController(
      text: widget.defaults.localOriginalRetentionDays.toString(),
    );
    _syncOnWrite = widget.defaults.syncOnWrite;
    _syncOriginals = widget.defaults.syncOriginals;
    _downloadOriginals = widget.defaults.downloadOriginals;
  }

  @override
  void dispose() {
    _remoteFolderController.dispose();
    _minimumIntervalController.dispose();
    _maxDestructiveActionsController.dispose();
    _localOriginalRetentionController.dispose();
    super.dispose();
  }

  Future<void> _disconnect() async {
    final disconnected = await widget.onDisconnect();
    if (disconnected && mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _cleanLocalOriginals() async {
    if (_isCleaningOriginals) {
      return;
    }
    final retentionDays =
        int.tryParse(_localOriginalRetentionController.text.trim()) ??
        widget.defaults.localOriginalRetentionDays;
    setState(() {
      _isCleaningOriginals = true;
    });
    try {
      final result = await widget.onCleanLocalOriginals(
        Duration(days: retentionDays < 1 ? 1 : retentionDays),
      );
      if (!mounted) {
        return;
      }
      final freedMb = (result.freedBytes / (1024 * 1024)).toStringAsFixed(1);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已清理 ${result.deletedOriginals} 张本地原图，释放 $freedMb MB'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isCleaningOriginals = false;
        });
      }
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
            const SizedBox(height: 24),
            DiaryPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SwitchListTile(
                    value: _syncOriginals,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('同步原图到 OneDrive'),
                    onChanged: (value) {
                      setState(() {
                        _syncOriginals = value;
                      });
                    },
                  ),
                  SwitchListTile(
                    value: _downloadOriginals,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('从 OneDrive 下载原图'),
                    onChanged: (value) {
                      setState(() {
                        _downloadOriginals = value;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _localOriginalRetentionController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '本地原图保留天数',
                      hintText: '默认 30',
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _isCleaningOriginals
                        ? null
                        : _cleanLocalOriginals,
                    icon: const Icon(Icons.cleaning_services_rounded),
                    label: Text(_isCleaningOriginals ? '正在清理...' : '清理过期本地原图'),
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
                    final localOriginalRetentionDays =
                        int.tryParse(
                          _localOriginalRetentionController.text.trim(),
                        ) ??
                        30;
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
                        syncOriginals: _syncOriginals,
                        downloadOriginals: _downloadOriginals,
                        localOriginalRetentionDays:
                            localOriginalRetentionDays < 1
                            ? 1
                            : localOriginalRetentionDays,
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
