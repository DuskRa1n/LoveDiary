import 'package:flutter/material.dart';

import '../sync/diary_sync_executor.dart';
import 'diary_design.dart';

enum SyncConflictResolutionChoice { keepLocal, useRemote }

class SyncConflictResolutionResult {
  const SyncConflictResolutionResult({required this.decisions});

  final Map<String, SyncConflictResolutionChoice> decisions;
}

class SyncConflictPage extends StatefulWidget {
  const SyncConflictPage({
    super.key,
    required this.conflictPaths,
    this.conflictDetails = const [],
  });

  final List<String> conflictPaths;
  final List<SyncConflictDetail> conflictDetails;

  @override
  State<SyncConflictPage> createState() => _SyncConflictPageState();
}

class _SyncConflictPageState extends State<SyncConflictPage> {
  late final Map<String, SyncConflictResolutionChoice> _decisions = {
    for (final path in widget.conflictPaths)
      path: SyncConflictResolutionChoice.keepLocal,
  };
  late final Map<String, SyncConflictDetail> _detailByPath = {
    for (final detail in widget.conflictDetails) detail.relativePath: detail,
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
                    Builder(
                      builder: (context) {
                        final path = widget.conflictPaths[i];
                        return _ConflictRow(
                          relativePath: path,
                          detail: _detailByPath[path],
                          choice: _decisions[path]!,
                          onChanged: (choice) {
                            setState(() {
                              _decisions[path] = choice;
                            });
                          },
                        );
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
    required this.detail,
    required this.choice,
    required this.onChanged,
  });

  final String relativePath;
  final SyncConflictDetail? detail;
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
        if (detail != null) ...[
          const SizedBox(height: 12),
          _ConflictDetailPanel(detail: detail!),
        ],
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

class _ConflictDetailPanel extends StatelessWidget {
  const _ConflictDetailPanel({required this.detail});

  final SyncConflictDetail detail;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: DiaryPalette.paper.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: DiaryPalette.line.withValues(alpha: 0.8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (detail.reason != null && detail.reason!.isNotEmpty) ...[
            Text(
              _reasonLabel(detail.reason!),
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: DiaryPalette.rose,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
          ],
          _ConflictSideBlock(label: '本地', preview: detail.local),
          const SizedBox(height: 8),
          _ConflictSideBlock(label: '云端', preview: detail.remote),
        ],
      ),
    );
  }
}

class _ConflictSideBlock extends StatelessWidget {
  const _ConflictSideBlock({required this.label, required this.preview});

  final String label;
  final SyncConflictSidePreview? preview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (preview == null) {
      return Text(
        '$label：无文件',
        style: theme.textTheme.bodySmall?.copyWith(color: DiaryPalette.wine),
      );
    }

    final title = preview!.title?.isNotEmpty == true
        ? preview!.title!
        : preview!.isBinary
        ? '附件文件'
        : 'JSON 文件';
    final chips = <String>[
      _formatDateTime(preview!.modifiedAt),
      _formatBytes(preview!.size),
      if (preview!.mood?.isNotEmpty == true) preview!.mood!,
      if (preview!.revision?.isNotEmpty == true)
        'rev ${_compactRevision(preview!.revision!)}',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$label：$title',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: DiaryPalette.ink,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          chips.join(' · '),
          style: theme.textTheme.bodySmall?.copyWith(
            color: DiaryPalette.wine,
            height: 1.35,
          ),
        ),
        if (preview!.contentPreview?.isNotEmpty == true) ...[
          const SizedBox(height: 4),
          Text(
            preview!.contentPreview!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: DiaryPalette.wine,
              height: 1.35,
            ),
          ),
        ],
      ],
    );
  }
}

String _formatDateTime(DateTime value) {
  String two(int input) => input.toString().padLeft(2, '0');
  return '${value.year}.${two(value.month)}.${two(value.day)} ${two(value.hour)}:${two(value.minute)}';
}

String _formatBytes(int bytes) {
  if (bytes < 1024) {
    return '$bytes B';
  }
  final kb = bytes / 1024;
  if (kb < 1024) {
    return '${kb.toStringAsFixed(kb >= 10 ? 0 : 1)} KB';
  }
  final mb = kb / 1024;
  return '${mb.toStringAsFixed(mb >= 10 ? 1 : 2)} MB';
}

String _compactRevision(String revision) {
  if (revision.length <= 10) {
    return revision;
  }
  return '${revision.substring(0, 6)}...${revision.substring(revision.length - 4)}';
}

String _reasonLabel(String reason) {
  return switch (reason) {
    'remote_deleted_while_local_changed' => '云端删除，本地也有修改',
    'local_and_remote_changed' => '本地和云端都修改过',
    'initial_sync_unverified_same_timestamp' => '首次同步发现同名差异',
    _ => '需要确认最终版本',
  };
}
