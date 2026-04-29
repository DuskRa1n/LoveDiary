part of '../../app.dart';

class ProfileSetupPage extends StatefulWidget {
  const ProfileSetupPage({
    super.key,
    required this.initialProfile,
    required this.isFirstSetup,
    this.canRestoreFromOneDrive = false,
    this.hasOneDriveConfig = false,
    this.onRestoreFromOneDrive,
    this.onComplete,
    this.writeLockedListenable,
    this.onWriteBlocked,
  });

  final CoupleProfile initialProfile;
  final bool isFirstSetup;
  final bool canRestoreFromOneDrive;
  final bool hasOneDriveConfig;
  final Future<void> Function()? onRestoreFromOneDrive;
  final Future<void> Function(CoupleProfile profile)? onComplete;
  final ValueListenable<bool>? writeLockedListenable;
  final VoidCallback? onWriteBlocked;

  @override
  State<ProfileSetupPage> createState() => _ProfileSetupPageState();
}

class _ProfileSetupPageState extends State<ProfileSetupPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _maleNameController;
  late final TextEditingController _femaleNameController;
  late DateTime _togetherSince;
  late String _currentUserRole;

  @override
  void initState() {
    super.initState();
    widget.writeLockedListenable?.addListener(_handleWriteLockChanged);
    _maleNameController = TextEditingController(
      text: widget.initialProfile.maleName,
    );
    _femaleNameController = TextEditingController(
      text: widget.initialProfile.femaleName,
    );
    _togetherSince = widget.initialProfile.togetherSince;
    _currentUserRole = widget.initialProfile.currentUserRole;
  }

  @override
  void dispose() {
    widget.writeLockedListenable?.removeListener(_handleWriteLockChanged);
    _maleNameController.dispose();
    _femaleNameController.dispose();
    super.dispose();
  }

  bool get _isWriteLocked => widget.writeLockedListenable?.value ?? false;

  void _handleWriteLockChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  bool _guardWritableAction() {
    if (!_isWriteLocked) {
      return true;
    }
    widget.onWriteBlocked?.call();
    return false;
  }

  Future<void> _pickTogetherSince() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _togetherSince,
      firstDate: DateTime(2010),
      lastDate: DateTime.now(),
      helpText: '选择在一起的日期',
      cancelText: '取消',
      confirmText: '确定',
    );

    if (picked == null) {
      return;
    }

    setState(() {
      _togetherSince = picked;
    });
  }

  Future<void> _submit() async {
    if (!_guardWritableAction()) {
      return;
    }

    if (!_formKey.currentState!.validate()) {
      return;
    }

    final profile = widget.initialProfile.copyWith(
      maleName: _maleNameController.text.trim(),
      femaleName: _femaleNameController.text.trim(),
      currentUserRole: _currentUserRole,
      togetherSince: _togetherSince,
      isOnboarded: true,
    );

    if (widget.onComplete != null) {
      await widget.onComplete!(profile);
      return;
    }

    if (!mounted) {
      return;
    }
    Navigator.of(context).pop(profile);
  }

  @override
  Widget build(BuildContext context) {
    final isWriteLocked = _isWriteLocked;
    return Scaffold(
      appBar: widget.isFirstSetup ? null : AppBar(title: const Text('编辑我们')),
      body: SafeArea(
        top: widget.isFirstSetup,
        bottom: false,
        child: Form(
          key: _formKey,
          child: DiaryPage(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DiaryCompactHeader(
                  eyebrow: widget.isFirstSetup ? '初始设置' : '编辑资料',
                  title: widget.isFirstSetup ? '先把资料填好' : '更新资料',
                ),
                if (widget.isFirstSetup &&
                    widget.canRestoreFromOneDrive &&
                    widget.onRestoreFromOneDrive != null) ...[
                  const SizedBox(height: 20),
                  DiaryPanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '已有 OneDrive 数据？',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                color: DiaryPalette.ink,
                                fontWeight: FontWeight.w900,
                              ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          widget.hasOneDriveConfig
                              ? '可以先进入主页面并从 OneDrive 恢复，云端资料拉下来后会自动更新这里。'
                              : '可以先进入主页面，之后在“我们”页手动连接 OneDrive，连接完成后自动恢复已有数据。',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: DiaryPalette.wine,
                                height: 1.45,
                              ),
                        ),
                        const SizedBox(height: 14),
                        FilledButton.icon(
                          onPressed: widget.onRestoreFromOneDrive,
                          icon: const Icon(Icons.cloud_download_rounded),
                          label: const Text('从 OneDrive 恢复'),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                DiaryPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextFormField(
                        controller: _maleNameController,
                        decoration: const InputDecoration(labelText: '他叫什么'),
                        validator: _nonEmptyValidator,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _femaleNameController,
                        decoration: const InputDecoration(labelText: '她叫什么'),
                        validator: _nonEmptyValidator,
                      ),
                      const SizedBox(height: 16),
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment<String>(
                            value: 'male',
                            label: Text('我是他'),
                          ),
                          ButtonSegment<String>(
                            value: 'female',
                            label: Text('我是她'),
                          ),
                        ],
                        selected: {_currentUserRole},
                        onSelectionChanged: (selection) {
                          setState(() {
                            _currentUserRole = selection.first;
                          });
                        },
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        onPressed: _pickTogetherSince,
                        icon: const Icon(Icons.favorite_rounded),
                        label: Text(
                          '在一起的日期：${formatDiaryDate(_togetherSince)}',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: isWriteLocked ? widget.onWriteBlocked : _submit,
                  child: Text(
                    isWriteLocked
                        ? '同步中，稍后保存'
                        : widget.isFirstSetup
                        ? '开始记录'
                        : '保存资料',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String? _nonEmptyValidator(String? value) {
    if (value == null || value.trim().isEmpty) {
      return '这里不能为空';
    }
    return null;
  }
}
