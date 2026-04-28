import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../sync/onedrive/onedrive_auth_service.dart';
import '../sync/onedrive/onedrive_models.dart';
import 'diary_design.dart';

class OneDriveConnectPage extends StatefulWidget {
  const OneDriveConnectPage({
    super.key,
    required this.authService,
    required this.clientId,
    required this.tenant,
    required this.remoteFolder,
  });

  final OneDriveAuthService authService;
  final String clientId;
  final String tenant;
  final String remoteFolder;

  @override
  State<OneDriveConnectPage> createState() => _OneDriveConnectPageState();
}

class _OneDriveConnectPageState extends State<OneDriveConnectPage> {
  late final TextEditingController _remoteFolderController;

  OneDriveDeviceCodeSession? _session;
  bool _isLoading = false;
  bool _isCompleting = false;
  bool _isOpeningBrowser = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _remoteFolderController = TextEditingController(text: widget.remoteFolder);
  }

  @override
  void dispose() {
    _remoteFolderController.dispose();
    super.dispose();
  }

  String _normalizedRemoteFolder() {
    final value = _remoteFolderController.text.trim();
    return value.isEmpty ? 'love_diary' : value;
  }

  Future<void> _startFlow() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _session = null;
    });

    try {
      final session = await widget.authService.startDeviceCodeFlow(
        clientId: widget.clientId,
        tenant: widget.tenant,
        remoteFolder: _normalizedRemoteFolder(),
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _session = session;
      });
    } on OneDriveAuthException catch (error) {
      if (mounted) {
        setState(() {
          _error = error.message;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = '连接 OneDrive 失败：$error';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _copy(String label, String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$label 已复制')));
  }

  Future<void> _openVerificationPage(
    OneDriveDeviceCodeSession session, {
    bool silentFailure = false,
  }) async {
    if (_isOpeningBrowser) {
      return;
    }

    final target = session.verificationUriComplete ?? session.verificationUri;
    final uri = Uri.tryParse(target);
    if (uri == null) {
      if (!silentFailure && mounted) {
        setState(() {
          _error = '验证地址无效，请手动复制地址到浏览器打开。';
        });
      }
      return;
    }

    setState(() {
      _isOpeningBrowser = true;
    });

    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched && !silentFailure && mounted) {
        setState(() {
          _error = '无法自动打开浏览器，请手动复制验证地址。';
        });
      }
    } catch (error) {
      if (!silentFailure && mounted) {
        setState(() {
          _error = '打开浏览器失败：$error';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isOpeningBrowser = false;
        });
      }
    }
  }

  Future<void> _completeFlow() async {
    final session = _session;
    if (session == null || _isCompleting) {
      return;
    }

    setState(() {
      _isCompleting = true;
      _error = null;
    });

    try {
      final config = await widget.authService.completeDeviceCodeFlow(session);
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(config);
    } on OneDriveAuthException catch (error) {
      if (mounted) {
        setState(() {
          _error = error.message;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = '完成 OneDrive 授权失败：$error';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isCompleting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;

    return Scaffold(
      appBar: AppBar(title: const Text('连接 OneDrive')),
      body: DiaryPage(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const DiaryCompactHeader(eyebrow: 'OneDrive', title: '连接云端同步'),
            const SizedBox(height: 22),
            DiaryPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '同步目录',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: DiaryPalette.ink,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _remoteFolderController,
                    decoration: const InputDecoration(
                      labelText: '远端目录',
                      hintText: '默认 love_diary',
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '两台设备需要使用同一个目录名。建议先不要频繁切换目录。',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: DiaryPalette.wine),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _isLoading || _isCompleting ? null : _startFlow,
                    icon: const Icon(Icons.login_rounded),
                    label: Text(_isLoading ? '正在获取验证码...' : '获取验证码'),
                  ),
                ],
              ),
            ),
            if (session != null) ...[
              const SizedBox(height: 22),
              const DiarySectionHeader(title: '完成授权'),
              const SizedBox(height: 14),
              DiaryPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _ConnectStep(
                      index: '1',
                      title: '打开验证地址',
                      body: session.verificationUri,
                      actionLabel: _isOpeningBrowser ? '正在打开...' : '打开浏览器',
                      onAction: _isOpeningBrowser
                          ? null
                          : () => _openVerificationPage(session),
                    ),
                    const Divider(height: 26, color: DiaryPalette.line),
                    _ConnectStep(
                      index: '2',
                      title: '输入验证码',
                      body: session.userCode,
                      actionLabel: '复制验证码',
                      onAction: () => _copy('验证码', session.userCode),
                    ),
                    const Divider(height: 26, color: DiaryPalette.line),
                    _ConnectStep(
                      index: '3',
                      title: '回到应用确认',
                      body: '浏览器里显示授权完成后，再点击下面按钮继续。',
                      actionLabel: _isCompleting ? '正在确认...' : '我已完成授权',
                      onAction: _isCompleting ? null : _completeFlow,
                    ),
                  ],
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 16),
              DiaryPanel(
                child: Text(
                  _error!,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: DiaryPalette.rose,
                    height: 1.45,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 18),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                if (session != null)
                  OutlinedButton.icon(
                    onPressed: _isLoading || _isCompleting ? null : _startFlow,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('重新获取验证码'),
                  ),
                TextButton(
                  onPressed: _isCompleting
                      ? null
                      : () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ConnectStep extends StatelessWidget {
  const _ConnectStep({
    required this.index,
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.onAction,
  });

  final String index;
  final String title;
  final String body;
  final String actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: const BoxDecoration(
            color: DiaryPalette.mist,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            index,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: DiaryPalette.rose,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: DiaryPalette.ink,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              SelectableText(
                body,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: DiaryPalette.wine,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton(onPressed: onAction, child: Text(actionLabel)),
            ],
          ),
        ),
      ],
    );
  }
}
