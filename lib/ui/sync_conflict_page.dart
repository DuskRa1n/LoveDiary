import 'package:flutter/material.dart';

import 'diary_design.dart';

enum SyncConflictResolutionChoice { keepLocal, useRemote }

class SyncConflictResolutionResult {
  const SyncConflictResolutionResult({required this.decisions});

  final Map<String, SyncConflictResolutionChoice> decisions;
}

class SyncConflictPage extends StatefulWidget {
  const SyncConflictPage({super.key, required this.conflictPaths});

  final List<String> conflictPaths;

  @override
  State<SyncConflictPage> createState() => _SyncConflictPageState();
}

class _SyncConflictPageState extends State<SyncConflictPage> {
  late final Map<String, SyncConflictResolutionChoice> _decisions = {
    for (final path in widget.conflictPaths)
      path: SyncConflictResolutionChoice.keepLocal,
  };

  void _applyToAll(SyncConflictResolutionChoice choice) {
    setState(() {
      for (final path in widget.conflictPaths) {
        _decisions[path] = choice;
      }
    });
  }

  void _submit() {
    Navigator.of(context).pop(
      SyncConflictResolutionResult(
        decisions: Map<String, SyncConflictResolutionChoice>.from(_decisions),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('同步冲突')),
      body: DiaryPage(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DiaryCompactHeader(
              eyebrow: '需要你确认',
              title: '发现 ${widget.conflictPaths.length} 个冲突',
              footer: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  DiaryBadge(label: '支持逐条处理'),
                  DiaryBadge(label: '不会自动覆盖', tone: DiaryBadgeTone.ink),
                ],
              ),
            ),
            const SizedBox(height: 22),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                OutlinedButton.icon(
                  onPressed: () =>
                      _applyToAll(SyncConflictResolutionChoice.keepLocal),
                  icon: const Icon(Icons.upload_rounded),
                  label: const Text('全部保留本地'),
                ),
                OutlinedButton.icon(
                  onPressed: () =>
                      _applyToAll(SyncConflictResolutionChoice.useRemote),
                  icon: const Icon(Icons.cloud_download_rounded),
                  label: const Text('全部采用云端'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            DiaryPanel(
              child: Column(
                children: [
                  for (var i = 0; i < widget.conflictPaths.length; i++) ...[
                    _ConflictRow(
                      relativePath: widget.conflictPaths[i],
                      choice: _decisions[widget.conflictPaths[i]]!,
                      onChanged: (choice) {
                        setState(() {
                          _decisions[widget.conflictPaths[i]] = choice;
                        });
                      },
                    ),
                    if (i != widget.conflictPaths.length - 1)
                      const Divider(height: 20, color: DiaryPalette.line),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  onPressed: _submit,
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('应用这些选择'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('稍后再处理'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ConflictRow extends StatelessWidget {
  const _ConflictRow({
    required this.relativePath,
    required this.choice,
    required this.onChanged,
  });

  final String relativePath;
  final SyncConflictResolutionChoice choice;
  final ValueChanged<SyncConflictResolutionChoice> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                color: DiaryPalette.mist,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: const Icon(
                Icons.warning_amber_rounded,
                color: DiaryPalette.rose,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    relativePath,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: DiaryPalette.ink,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '如果你确定这份内容是最新的，就选择它作为最终版本。',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: DiaryPalette.wine,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            ChoiceChip(
              label: const Text('保留本地'),
              selected: choice == SyncConflictResolutionChoice.keepLocal,
              onSelected: (_) =>
                  onChanged(SyncConflictResolutionChoice.keepLocal),
            ),
            ChoiceChip(
              label: const Text('采用云端'),
              selected: choice == SyncConflictResolutionChoice.useRemote,
              onSelected: (_) =>
                  onChanged(SyncConflictResolutionChoice.useRemote),
            ),
          ],
        ),
      ],
    );
  }
}
