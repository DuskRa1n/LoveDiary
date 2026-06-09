import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../sync_models.dart';
import '../sync_remote_source.dart';
import 'onedrive_auth_service.dart';
import 'onedrive_models.dart';

class OneDriveRemoteSource implements DiarySyncRemoteSource {
  OneDriveRemoteSource({required this.authService});

  static const _graphBaseUrl = 'https://graph.microsoft.com/v1.0';
  static const _simpleUploadLimitBytes = 4 * 1024 * 1024;
  static const _uploadChunkSize = 320 * 1024 * 20;
  static const _maxRequestAttempts = 4;
  static const _requestTimeout = Duration(seconds: 45);
  static const _downloadUrlField = '@microsoft.graph.downloadUrl';
  static const _deltaSelectFields =
      'id,name,parentReference,eTag,size,lastModifiedDateTime,file,folder,deleted,$_downloadUrlField';
  static const _childrenSelectFields =
      'id,name,parentReference,eTag,size,lastModifiedDateTime,file,folder,$_downloadUrlField';

  final OneDriveAuthService authService;
  final HttpClient _httpClient = HttpClient()
    ..connectionTimeout = _requestTimeout
    ..idleTimeout = const Duration(seconds: 30);
  final Set<String> _knownRemoteFolderPaths = <String>{};
  final Map<String, String> _downloadUrlsByPath = <String, String>{};

  OneDriveSyncConfig? _cachedConfig;
  String? _cachedAccessToken;

  void dispose() {
    _httpClient.close();
  }

  @override
  Future<void> persistSnapshot(List<LocalSyncFile> localFiles) async {}

  Future<OneDriveSyncConfig> _requireConfig() async {
    final cached = _cachedConfig;
    if (cached != null) {
      return cached;
    }
    final config = await authService.requireConfig();
    _cachedConfig = config;
    return config;
  }

  Future<String> _getAccessToken() async {
    final cached = _cachedAccessToken;
    final cachedConfig = _cachedConfig;
    if (cached != null &&
        cached.isNotEmpty &&
        cachedConfig != null &&
        !cachedConfig.isExpired) {
      return cached;
    }
    _cachedAccessToken = null;
    final accessToken = await authService.getValidAccessToken();
    _cachedAccessToken = accessToken;
    _cachedConfig = await authService.requireConfig();
    return accessToken;
  }

  @override
  Future<RemoteSyncSnapshot> fetchSnapshot({
    SyncState? baseline,
    SyncProgressCallback? onProgress,
    SyncCancellationCheck? checkCancelled,
  }) async {
    checkCancelled?.call();
    onProgress?.call(0, 'OneDrive：检查配置和授权');
    final config = await _requireConfig();
    final accessToken = await _getAccessToken();

    if (baseline?.canUseDelta ?? false) {
      try {
        onProgress?.call(0.12, 'OneDrive：读取增量变更');
        final snapshot = await _fetchDeltaSnapshot(
          accessToken: accessToken,
          baseline: baseline!,
          onProgress: onProgress,
          checkCancelled: checkCancelled,
        );
        _rememberRemoteFolders(config.remoteFolder, snapshot.remoteNodes);
        onProgress?.call(
          1,
          'OneDrive：增量扫描完成，发现 ${snapshot.files.length} 个远端文件',
        );
        return snapshot;
      } on OneDriveAuthException {
        onProgress?.call(0.18, 'OneDrive：增量基线失效，改为全量扫描');
      }
    }

    onProgress?.call(0.2, 'OneDrive：开始全量扫描远端目录');
    final snapshot = await _fetchFullSnapshot(
      accessToken: accessToken,
      config: config,
      baseline: baseline,
      onProgress: onProgress,
      checkCancelled: checkCancelled,
    );
    _rememberRemoteFolders(config.remoteFolder, snapshot.remoteNodes);
    onProgress?.call(1, 'OneDrive：全量扫描完成，发现 ${snapshot.files.length} 个远端文件');
    return snapshot;
  }

  @override
  Future<void> uploadFile({
    required String relativePath,
    required String absolutePath,
    required bool isBinary,
    SyncCancellationCheck? checkCancelled,
  }) async {
    checkCancelled?.call();
    final config = await _requireConfig();
    final accessToken = await _getAccessToken();
    final localFile = File(absolutePath);
    final stat = await localFile.stat();
    if (stat.size == 0) {
      throw const OneDriveAuthException('OneDrive 不支持在此同步流程中上传空文件。');
    }

    await _ensureRemoteParentFolders(
      accessToken: accessToken,
      remoteFolder: config.remoteFolder,
      relativePath: relativePath,
    );

    if (stat.size <= _simpleUploadLimitBytes) {
      final bytes = await localFile.readAsBytes();
      await _putFileContent(
        uri: _buildPathUri(
          config.remoteFolder,
          relativePath,
          suffix: 'content',
        ),
        accessToken: accessToken,
        bytes: bytes,
        isBinary: isBinary,
      );
      return;
    }

    final uploadSessionResponse = await _sendRequest(
      method: 'POST',
      uri: _buildPathUri(
        config.remoteFolder,
        relativePath,
        suffix: 'createUploadSession',
      ),
      accessToken: accessToken,
      headers: {HttpHeaders.contentTypeHeader: 'application/json'},
      body: utf8.encode(
        jsonEncode({
          'item': {'@microsoft.graph.conflictBehavior': 'replace'},
        }),
      ),
    );
    final uploadSessionJson = _decodeJson(uploadSessionResponse.body);
    if (uploadSessionResponse.statusCode < 200 ||
        uploadSessionResponse.statusCode >= 300) {
      throw OneDriveAuthException(
        uploadSessionJson['error']?['message'] as String? ??
            '创建 OneDrive 上传会话失败。',
      );
    }

    final uploadUrl = uploadSessionJson['uploadUrl'] as String;
    final reader = await localFile.open();
    try {
      var start = 0;
      while (start < stat.size) {
        checkCancelled?.call();
        final endExclusive = (start + _uploadChunkSize > stat.size)
            ? stat.size
            : start + _uploadChunkSize;
        await reader.setPosition(start);
        final chunk = await reader.read(endExclusive - start);
        final response = await _sendAbsoluteRequest(
          method: 'PUT',
          uri: Uri.parse(uploadUrl),
          headers: {
            HttpHeaders.contentLengthHeader: chunk.length.toString(),
            HttpHeaders.contentRangeHeader:
                'bytes $start-${endExclusive - 1}/${stat.size}',
          },
          body: chunk,
        );
        if (response.statusCode != 200 &&
            response.statusCode != 201 &&
            response.statusCode != 202) {
          final payload = _decodeJson(response.body);
          throw OneDriveAuthException(
            payload['error']?['message'] as String? ?? 'OneDrive 分块上传失败。',
          );
        }
        start = endExclusive;
      }
    } finally {
      await reader.close();
    }
  }

  @override
  Future<void> downloadFile({
    required String relativePath,
    required String targetAbsolutePath,
    required bool isBinary,
    SyncCancellationCheck? checkCancelled,
  }) async {
    checkCancelled?.call();
    final targetFile = File(targetAbsolutePath);
    final cachedDownloadUrl = _downloadUrlsByPath[relativePath];
    if (cachedDownloadUrl != null && cachedDownloadUrl.isNotEmpty) {
      try {
        await _downloadAbsoluteFile(
          uri: Uri.parse(cachedDownloadUrl),
          targetFile: targetFile,
          relativePath: relativePath,
          checkCancelled: checkCancelled,
        );
        return;
      } on OneDriveAuthException {
        _downloadUrlsByPath.remove(relativePath);
      }
    }

    final downloadUrl = await _fetchDownloadUrl(
      relativePath: relativePath,
      checkCancelled: checkCancelled,
    );
    await _downloadAbsoluteFile(
      uri: Uri.parse(downloadUrl),
      targetFile: targetFile,
      relativePath: relativePath,
      checkCancelled: checkCancelled,
    );
  }

  Future<String> _fetchDownloadUrl({
    required String relativePath,
    SyncCancellationCheck? checkCancelled,
  }) async {
    checkCancelled?.call();
    final config = await _requireConfig();
    final accessToken = await _getAccessToken();
    final metadataResponse = await _sendRequest(
      method: 'GET',
      uri: _buildPathUri(config.remoteFolder, relativePath),
      accessToken: accessToken,
    );
    final metadataPayload = _decodeJson(metadataResponse.body);
    if (metadataResponse.statusCode < 200 ||
        metadataResponse.statusCode >= 300) {
      throw OneDriveAuthException(
        metadataPayload['error']?['message'] as String? ??
            '读取 $relativePath 的 OneDrive 元数据失败。',
      );
    }

    final downloadUrl = metadataPayload[_downloadUrlField] as String?;
    if (downloadUrl == null || downloadUrl.isEmpty) {
      throw OneDriveAuthException('OneDrive 未返回 $relativePath 的下载链接。');
    }

    _downloadUrlsByPath[relativePath] = downloadUrl;
    return downloadUrl;
  }

  @override
  Future<void> deleteFile(
    String relativePath, {
    SyncCancellationCheck? checkCancelled,
  }) async {
    checkCancelled?.call();
    final config = await _requireConfig();
    final accessToken = await _getAccessToken();
    final response = await _sendRequest(
      method: 'DELETE',
      uri: _buildPathUri(config.remoteFolder, relativePath),
      accessToken: accessToken,
    );
    if (response.statusCode == 404 || response.statusCode == 204) {
      return;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final payload = _decodeJson(response.body);
      throw OneDriveAuthException(
        payload['error']?['message'] as String? ??
            '从 OneDrive 删除 $relativePath 失败。',
      );
    }
  }

  Future<RemoteSyncSnapshot> _fetchFullSnapshot({
    required String accessToken,
    required OneDriveSyncConfig config,
    required SyncState? baseline,
    SyncProgressCallback? onProgress,
    SyncCancellationCheck? checkCancelled,
  }) async {
    checkCancelled?.call();
    onProgress?.call(0.24, 'OneDrive：定位远端目录“${config.remoteFolder}”');
    final rootFolder = await _tryGetRemoteFolder(
      accessToken: accessToken,
      relativePath: config.remoteFolder,
    );
    if (rootFolder == null) {
      if (baseline?.lastKnownRemoteRevisions.isNotEmpty ?? false) {
        throw OneDriveAuthException(
          'OneDrive 远端目录“${config.remoteFolder}”不存在，已停止本次同步以避免误删本地数据。',
        );
      }
      return const RemoteSyncSnapshot(cursor: null, files: []);
    }

    final rootId = rootFolder['id'] as String;
    final nodes = <String, OneDriveRemoteNode>{
      rootId: _buildRootNode(rootFolder, config.remoteFolder),
    };
    final files = <RemoteSyncFile>[];
    var scannedFolders = 0;
    var scannedFiles = 0;
    await _collectNodesRecursively(
      accessToken: accessToken,
      folderId: rootId,
      pathPrefix: '',
      nodes: nodes,
      sink: files,
      checkCancelled: checkCancelled,
      onItemScanned: (path, isFolder) {
        checkCancelled?.call();
        if (isFolder) {
          scannedFolders++;
        } else {
          scannedFiles++;
        }
        final activityCount = scannedFolders + scannedFiles;
        if (activityCount != 1 && activityCount % 5 != 0) {
          return;
        }
        final progress = 0.34 + activityCount / (activityCount + 80) * 0.42;
        final displayPath = path.isEmpty ? config.remoteFolder : path;
        onProgress?.call(
          progress,
          'OneDrive：扫描 $scannedFolders 个文件夹、$scannedFiles 个文件：${_compactDisplayPath(displayPath)}',
        );
      },
    );
    onProgress?.call(
      0.8,
      'OneDrive：扫描完成，$scannedFolders 个文件夹、$scannedFiles 个文件',
    );
    onProgress?.call(0.84, 'OneDrive：生成下次增量同步游标');
    final cursor = await _tryFetchDeltaCursor(
      accessToken: accessToken,
      remoteFolder: config.remoteFolder,
    );
    files.sort((a, b) => a.relativePath.compareTo(b.relativePath));
    return RemoteSyncSnapshot(
      cursor: cursor,
      files: files,
      remoteRootId: rootId,
      remoteNodes: nodes,
    );
  }

  Future<RemoteSyncSnapshot> _fetchDeltaSnapshot({
    required String accessToken,
    required SyncState baseline,
    SyncProgressCallback? onProgress,
    SyncCancellationCheck? checkCancelled,
  }) async {
    checkCancelled?.call();
    if (!baseline.canUseDelta) {
      throw const OneDriveAuthException('OneDrive 增量同步基线不完整。');
    }

    final nodes = {
      for (final entry in baseline.lastKnownRemoteNodes.entries)
        entry.key: entry.value,
    };
    final rootId = baseline.lastKnownRemoteRootId!;
    if (!nodes.containsKey(rootId)) {
      throw const OneDriveAuthException('OneDrive 远端根目录在基线中缺失。');
    }

    var nextUrl = baseline.lastKnownRemoteCursor!;
    String? deltaLink;
    var pageCount = 0;
    var changeCount = 0;
    while (nextUrl.isNotEmpty) {
      checkCancelled?.call();
      final response = await _sendRequest(
        method: 'GET',
        uri: Uri.parse(nextUrl),
        accessToken: accessToken,
      );
      final payload = _decodeJson(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw OneDriveAuthException(
          payload['error']?['message'] as String? ?? '读取 OneDrive 增量变更失败。',
        );
      }

      final pending = (payload['value'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
      pageCount++;
      changeCount += pending.length;
      final progress = 0.18 + pageCount / (pageCount + 8) * 0.52;
      onProgress?.call(
        progress,
        'OneDrive：处理增量第 $pageCount 页，$changeCount 项变更',
      );
      await _applyDeltaItems(
        nodes: nodes,
        rootId: rootId,
        items: pending,
        checkCancelled: checkCancelled,
      );
      await _yieldToEventLoop();
      checkCancelled?.call();

      nextUrl = payload['@odata.nextLink'] as String? ?? '';
      deltaLink = payload['@odata.deltaLink'] as String? ?? deltaLink;
    }

    if (deltaLink == null || deltaLink.isEmpty) {
      throw const OneDriveAuthException('OneDrive 未返回增量同步游标。');
    }

    onProgress?.call(0.82, 'OneDrive：根据 item id 重建远端路径');
    final files = _filesFromNodes(nodes);
    return RemoteSyncSnapshot(
      cursor: deltaLink,
      files: files,
      remoteRootId: rootId,
      remoteNodes: nodes,
    );
  }

  Future<void> _applyDeltaItems({
    required Map<String, OneDriveRemoteNode> nodes,
    required String rootId,
    required List<Map<String, dynamic>> items,
    SyncCancellationCheck? checkCancelled,
  }) async {
    final pending = [...items];
    while (pending.isNotEmpty) {
      checkCancelled?.call();
      var progressed = false;
      var processed = 0;
      for (var index = pending.length - 1; index >= 0; index--) {
        checkCancelled?.call();
        final item = pending[index];
        try {
          _applyDeltaItem(nodes: nodes, rootId: rootId, item: item);
          pending.removeAt(index);
          progressed = true;
          processed++;
          if (processed % 100 == 0) {
            await _yieldToEventLoop();
            checkCancelled?.call();
          }
        } on _DeferredDeltaItemException {
          continue;
        }
      }

      if (!progressed) {
        throw const OneDriveAuthException('OneDrive 增量基线在远端变更后不完整。');
      }
    }
  }

  void _applyDeltaItem({
    required Map<String, OneDriveRemoteNode> nodes,
    required String rootId,
    required Map<String, dynamic> item,
  }) {
    final itemId = item['id'] as String?;
    if (itemId == null || itemId.isEmpty) {
      throw const OneDriveAuthException('OneDrive 增量项缺少 id。');
    }

    if (item['deleted'] != null) {
      _removeNodeAndDescendants(nodes, itemId);
      return;
    }

    final existingNode = nodes[itemId];
    final isFolder = item['folder'] != null;
    final name = (item['name'] as String?) ?? existingNode?.name;
    if (name == null || name.isEmpty) {
      throw const OneDriveAuthException('OneDrive 增量项缺少有效名称。');
    }

    final parentItemId = itemId == rootId
        ? null
        : ((item['parentReference'] as Map?)?['id'] as String?) ??
              existingNode?.parentItemId ??
              (throw const _DeferredDeltaItemException());

    final relativePath = _buildRelativePath(
      nodes: nodes,
      rootId: rootId,
      parentItemId: parentItemId,
      itemName: name,
      itemId: itemId,
    );

    if (isFolder) {
      nodes[itemId] = OneDriveRemoteNode(
        itemId: itemId,
        parentItemId: parentItemId,
        name: name,
        isFolder: true,
        relativePath: relativePath,
      );
      _rebuildDescendantPaths(nodes, itemId, rootId);
      return;
    }

    final remoteFile = _remoteFileFromItem(relativePath, item);
    nodes[itemId] = OneDriveRemoteNode(
      itemId: itemId,
      parentItemId: parentItemId,
      name: name,
      isFolder: false,
      relativePath: relativePath,
      revision: remoteFile.revision,
      fingerprint: remoteFile.fingerprint,
      modifiedAt: remoteFile.modifiedAt,
      size: remoteFile.size,
      isBinary: remoteFile.isBinary,
    );
  }

  Future<void> _collectNodesRecursively({
    required String accessToken,
    required String folderId,
    required String pathPrefix,
    required Map<String, OneDriveRemoteNode> nodes,
    required List<RemoteSyncFile> sink,
    required SyncCancellationCheck? checkCancelled,
    required void Function(String path, bool isFolder) onItemScanned,
  }) async {
    String? nextUrl =
        '$_graphBaseUrl/me/drive/items/$folderId/children?\$select=$_childrenSelectFields';

    while (nextUrl != null) {
      checkCancelled?.call();
      final response = await _sendRequest(
        method: 'GET',
        uri: Uri.parse(nextUrl),
        accessToken: accessToken,
      );
      final payload = _decodeJson(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw OneDriveAuthException(
          payload['error']?['message'] as String? ?? '列出 OneDrive 文件夹子项失败。',
        );
      }

      final items = payload['value'] as List? ?? const [];
      for (var index = 0; index < items.length; index++) {
        checkCancelled?.call();
        final rawItem = items[index];
        final item = Map<String, dynamic>.from(rawItem as Map);
        final itemId = item['id'] as String? ?? '';
        final name = item['name'] as String? ?? '';
        if (itemId.isEmpty || name.isEmpty) {
          continue;
        }

        final relativePath = pathPrefix.isEmpty ? name : '$pathPrefix/$name';
        if (item['folder'] != null) {
          onItemScanned(relativePath, true);
          nodes[itemId] = OneDriveRemoteNode(
            itemId: itemId,
            parentItemId: folderId,
            name: name,
            isFolder: true,
            relativePath: relativePath,
          );
          await _collectNodesRecursively(
            accessToken: accessToken,
            folderId: itemId,
            pathPrefix: relativePath,
            nodes: nodes,
            sink: sink,
            checkCancelled: checkCancelled,
            onItemScanned: onItemScanned,
          );
          continue;
        }

        onItemScanned(relativePath, false);
        final remoteFile = _remoteFileFromItem(relativePath, item);
        sink.add(remoteFile);
        nodes[itemId] = OneDriveRemoteNode(
          itemId: itemId,
          parentItemId: folderId,
          name: name,
          isFolder: false,
          relativePath: relativePath,
          revision: remoteFile.revision,
          fingerprint: remoteFile.fingerprint,
          modifiedAt: remoteFile.modifiedAt,
          size: remoteFile.size,
          isBinary: remoteFile.isBinary,
        );
        if ((index + 1) % 50 == 0) {
          await _yieldToEventLoop();
        }
      }

      nextUrl = payload['@odata.nextLink'] as String?;
    }
  }

  Future<String?> _tryFetchDeltaCursor({
    required String accessToken,
    required String remoteFolder,
  }) async {
    try {
      var nextUrl = _deltaStartUri(remoteFolder).toString();
      String? deltaLink;
      while (nextUrl.isNotEmpty) {
        final response = await _sendRequest(
          method: 'GET',
          uri: Uri.parse(nextUrl),
          accessToken: accessToken,
        );
        final payload = _decodeJson(response.body);
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw OneDriveAuthException(
            payload['error']?['message'] as String? ?? '读取 OneDrive 增量游标失败。',
          );
        }
        nextUrl = payload['@odata.nextLink'] as String? ?? '';
        deltaLink = payload['@odata.deltaLink'] as String? ?? deltaLink;
      }
      return deltaLink;
    } on OneDriveAuthException {
      return null;
    }
  }

  Future<Map<String, dynamic>?> _tryGetRemoteFolder({
    required String accessToken,
    required String relativePath,
  }) async {
    final response = await _sendRequest(
      method: 'GET',
      uri: _buildPathUri(relativePath, ''),
      accessToken: accessToken,
    );
    if (response.statusCode == 404) {
      return null;
    }
    final payload = _decodeJson(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw OneDriveAuthException(
        payload['error']?['message'] as String? ?? '读取 OneDrive 文件夹元数据失败。',
      );
    }
    if (payload['folder'] == null) {
      throw OneDriveAuthException('OneDrive 路径 "$relativePath" 存在但不是文件夹。');
    }
    return payload;
  }

  Future<void> _ensureRemoteParentFolders({
    required String accessToken,
    required String remoteFolder,
    required String relativePath,
  }) async {
    final relativeSegments = relativePath
        .split('/')
        .where((segment) => segment.isNotEmpty)
        .toList();
    if (relativeSegments.isNotEmpty) {
      relativeSegments.removeLast();
    }

    final segments = [..._pathSegments(remoteFolder), ...relativeSegments];
    if (segments.isEmpty) {
      return;
    }

    final builtSegments = <String>[];
    for (final segment in segments) {
      final parentPath = _joinSegments(builtSegments);
      builtSegments.add(segment);
      final folderPath = _joinSegments(builtSegments);
      if (_knownRemoteFolderPaths.contains(folderPath)) {
        continue;
      }

      final existingFolder = await _tryGetRemoteFolder(
        accessToken: accessToken,
        relativePath: folderPath,
      );
      if (existingFolder != null) {
        _knownRemoteFolderPaths.add(folderPath);
        continue;
      }

      await _createFolderAtPath(
        accessToken: accessToken,
        parentPath: parentPath,
        folderName: segment,
      );
      _knownRemoteFolderPaths.add(folderPath);
    }
  }

  Future<void> _createFolderAtPath({
    required String accessToken,
    required String parentPath,
    required String folderName,
  }) async {
    final response = await _sendRequest(
      method: 'POST',
      uri: parentPath.isEmpty
          ? Uri.parse('$_graphBaseUrl/me/drive/special/approot/children')
          : _buildPathUri(parentPath, '', suffix: 'children'),
      accessToken: accessToken,
      headers: {HttpHeaders.contentTypeHeader: 'application/json'},
      body: utf8.encode(
        jsonEncode({
          'name': folderName,
          'folder': {},
          '@microsoft.graph.conflictBehavior': 'fail',
        }),
      ),
    );
    if (response.statusCode == 409) {
      return;
    }
    final payload = _decodeJson(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw OneDriveAuthException(
        payload['error']?['message'] as String? ??
            '创建 OneDrive 文件夹 $folderName 失败。',
      );
    }
  }

  void _rememberRemoteFolders(
    String remoteFolder,
    Map<String, OneDriveRemoteNode> nodes,
  ) {
    final remoteRoot = _joinSegments(_pathSegments(remoteFolder));
    if (remoteRoot.isEmpty) {
      return;
    }
    _knownRemoteFolderPaths.add(remoteRoot);
    for (final node in nodes.values) {
      if (!node.isFolder || node.relativePath.isEmpty) {
        continue;
      }
      _knownRemoteFolderPaths.add(
        _joinSegments([
          ..._pathSegments(remoteRoot),
          ..._pathSegments(node.relativePath),
        ]),
      );
    }
  }

  List<String> _pathSegments(String path) {
    return path
        .replaceAll('\\', '/')
        .split('/')
        .where((segment) => segment.trim().isNotEmpty)
        .toList();
  }

  String _joinSegments(List<String> segments) {
    return segments.where((segment) => segment.isNotEmpty).join('/');
  }

  Uri _buildPathUri(
    String remoteFolder,
    String relativePath, {
    String? suffix,
  }) {
    final encodedFolder = _encodePath(remoteFolder);
    final normalizedPath = relativePath
        .split('/')
        .where((segment) => segment.isNotEmpty)
        .join('/');
    final encodedRelativePath = _encodePath(normalizedPath);
    final path = encodedRelativePath.isEmpty
        ? encodedFolder
        : '$encodedFolder/$encodedRelativePath';
    final suffixPart = suffix == null ? '' : '/$suffix';
    return Uri.parse(
      '$_graphBaseUrl/me/drive/special/approot:/$path:$suffixPart',
    );
  }

  Uri _deltaStartUri(String remoteFolder) {
    // Keep delta calls inside the AppFolder namespace so the
    // Files.ReadWrite.AppFolder scope can issue and reuse cursors.
    final encodedPath = _encodePath(remoteFolder);
    final deltaPath = encodedPath.isEmpty
        ? 'special/approot/delta'
        : 'special/approot:/$encodedPath:/delta';
    return Uri.parse(
      '$_graphBaseUrl/me/drive/$deltaPath?\$select=$_deltaSelectFields',
    );
  }

  String _encodePath(String path) {
    return path
        .split('/')
        .where((segment) => segment.isNotEmpty)
        .map(Uri.encodeComponent)
        .join('/');
  }

  Future<void> _putFileContent({
    required Uri uri,
    required String accessToken,
    required List<int> bytes,
    required bool isBinary,
  }) async {
    final response = await _sendRequest(
      method: 'PUT',
      uri: uri,
      accessToken: accessToken,
      headers: {
        HttpHeaders.contentLengthHeader: bytes.length.toString(),
        HttpHeaders.contentTypeHeader: isBinary
            ? 'application/octet-stream'
            : 'application/json; charset=utf-8',
      },
      body: bytes,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final payload = _decodeJson(response.body);
      throw OneDriveAuthException(
        payload['error']?['message'] as String? ?? '上传文件到 OneDrive 失败。',
      );
    }
  }

  Future<_RawResponse> _sendRequest({
    required String method,
    required Uri uri,
    required String accessToken,
    Map<String, String>? headers,
    List<int>? body,
  }) async {
    var bearerToken = accessToken;
    for (var authAttempt = 0; authAttempt < 2; authAttempt++) {
      final response = await _sendAbsoluteRequest(
        method: method,
        uri: uri,
        headers: {
          HttpHeaders.authorizationHeader: 'Bearer $bearerToken',
          HttpHeaders.acceptHeader: 'application/json',
          ...?headers,
        },
        body: body,
      );
      if (response.statusCode != HttpStatus.unauthorized) {
        return response;
      }

      _cachedAccessToken = null;
      if (authAttempt == 0) {
        bearerToken = await authService.getValidAccessToken(forceRefresh: true);
        _cachedAccessToken = bearerToken;
        _cachedConfig = await authService.requireConfig();
        continue;
      }

      throw OneDriveAuthException(
        OneDriveAuthService.normalizeAuthErrorMessage(
          _graphErrorMessage(response.body),
          OneDriveAuthService.invalidAccessTokenMessage,
        ),
      );
    }

    throw const OneDriveAuthException(
      OneDriveAuthService.invalidAccessTokenMessage,
    );
  }

  Future<_RawResponse> _sendAbsoluteRequest({
    required String method,
    required Uri uri,
    Map<String, String>? headers,
    List<int>? body,
  }) async {
    Object? lastError;

    for (var attempt = 1; attempt <= _maxRequestAttempts; attempt++) {
      try {
        final request = await _httpClient
            .openUrl(method, uri)
            .timeout(_requestTimeout);
        headers?.forEach(request.headers.set);
        if (body != null && body.isNotEmpty) {
          if (!request.headers.chunkedTransferEncoding) {
            request.contentLength = body.length;
          }
          request.add(body);
        }
        final response = await request.close().timeout(_requestTimeout);
        final bytes = await _readResponseBytes(
          response,
        ).timeout(_requestTimeout);
        final rawResponse = _RawResponse(
          statusCode: response.statusCode,
          body: utf8.decode(bytes, allowMalformed: true),
          bytes: bytes,
          retryAfter: _readRetryAfter(response),
        );

        if (_isRetryableStatus(rawResponse.statusCode) &&
            attempt < _maxRequestAttempts) {
          await Future<void>.delayed(_retryDelay(attempt, rawResponse));
          continue;
        }

        return rawResponse;
      } catch (error) {
        lastError = error;
        if (error is OneDriveAuthException) {
          rethrow;
        }
        if (!_isRetryableNetworkError(error) ||
            attempt >= _maxRequestAttempts) {
          throw OneDriveAuthException(_networkErrorMessage(uri, error));
        }
        await Future<void>.delayed(_retryDelay(attempt, null));
      }
    }

    throw OneDriveAuthException(
      _networkErrorMessage(uri, lastError ?? 'unknown error'),
    );
  }

  Future<void> _downloadAbsoluteFile({
    required Uri uri,
    required File targetFile,
    required String relativePath,
    SyncCancellationCheck? checkCancelled,
  }) async {
    Object? lastError;

    for (var attempt = 1; attempt <= _maxRequestAttempts; attempt++) {
      checkCancelled?.call();
      final temporaryFile = File('${targetFile.path}.tmp');
      IOSink? sink;
      try {
        final request = await _httpClient
            .openUrl('GET', uri)
            .timeout(_requestTimeout);
        final response = await request.close().timeout(_requestTimeout);
        if (_isRetryableStatus(response.statusCode) &&
            attempt < _maxRequestAttempts) {
          await Future<void>.delayed(_retryDelay(attempt, null));
          continue;
        }
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw OneDriveAuthException('从 OneDrive 下载 $relativePath 失败。');
        }

        await temporaryFile.parent.create(recursive: true);
        sink = temporaryFile.openWrite();
        await for (final data in response.timeout(_requestTimeout)) {
          checkCancelled?.call();
          sink.add(data);
        }
        await sink.flush();
        await sink.close();
        sink = null;
        if (await targetFile.exists()) {
          await targetFile.delete();
        }
        await temporaryFile.rename(targetFile.path);
        return;
      } catch (error) {
        lastError = error;
        if (error is OneDriveAuthException) {
          rethrow;
        }
        if (!_isRetryableNetworkError(error) ||
            attempt >= _maxRequestAttempts) {
          throw OneDriveAuthException(_networkErrorMessage(uri, error));
        }
        await Future<void>.delayed(_retryDelay(attempt, null));
      } finally {
        if (sink != null) {
          await sink.close();
        }
        if (await temporaryFile.exists()) {
          await temporaryFile.delete();
        }
      }
    }

    throw OneDriveAuthException(
      _networkErrorMessage(uri, lastError ?? 'unknown error'),
    );
  }

  OneDriveRemoteNode _buildRootNode(
    Map<String, dynamic> rootFolder,
    String remoteFolder,
  ) {
    final normalizedRemoteFolder = remoteFolder
        .split('/')
        .where((segment) => segment.isNotEmpty)
        .toList();
    return OneDriveRemoteNode(
      itemId: rootFolder['id'] as String,
      parentItemId: null,
      name:
          rootFolder['name'] as String? ??
          (normalizedRemoteFolder.isEmpty
              ? remoteFolder
              : normalizedRemoteFolder.last),
      isFolder: true,
      relativePath: '',
    );
  }

  String _compactDisplayPath(String path) {
    const maxLength = 48;
    if (path.length <= maxLength) {
      return path;
    }
    final segments = path.split('/');
    if (segments.length >= 2) {
      final compact = '${segments.first}/.../${segments.last}';
      if (compact.length <= maxLength) {
        return compact;
      }
    }
    return '...${path.substring(path.length - maxLength + 3)}';
  }

  RemoteSyncFile _remoteFileFromItem(
    String relativePath,
    Map<String, dynamic> item,
  ) {
    final modifiedAt =
        DateTime.tryParse(item['lastModifiedDateTime'] as String? ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0);
    final fileFacet = item['file'] as Map<String, dynamic>? ?? const {};
    final hashes = fileFacet['hashes'] as Map<String, dynamic>? ?? const {};
    final fingerprint =
        (hashes['sha1Hash'] as String?) ??
        (hashes['quickXorHash'] as String?) ??
        '${item['size']}:${modifiedAt.millisecondsSinceEpoch}';
    final downloadUrl = item[_downloadUrlField] as String?;
    if (downloadUrl == null || downloadUrl.isEmpty) {
      _downloadUrlsByPath.remove(relativePath);
    } else {
      _downloadUrlsByPath[relativePath] = downloadUrl;
    }

    return RemoteSyncFile(
      relativePath: relativePath,
      revision: item['eTag'] as String? ?? item['id'] as String,
      fingerprint: fingerprint,
      modifiedAt: modifiedAt,
      size: (item['size'] as num?)?.toInt() ?? 0,
      isBinary: !relativePath.endsWith('.json'),
    );
  }

  List<RemoteSyncFile> _filesFromNodes(Map<String, OneDriveRemoteNode> nodes) {
    final files =
        nodes.values
            .map((node) => node.remoteFile)
            .whereType<RemoteSyncFile>()
            .toList()
          ..sort((a, b) => a.relativePath.compareTo(b.relativePath));
    return files;
  }

  String _buildRelativePath({
    required Map<String, OneDriveRemoteNode> nodes,
    required String rootId,
    required String? parentItemId,
    required String itemName,
    required String itemId,
  }) {
    if (itemId == rootId) {
      return '';
    }
    if (parentItemId == null) {
      throw const _DeferredDeltaItemException();
    }
    if (parentItemId == rootId) {
      return itemName;
    }

    final parentNode = nodes[parentItemId];
    if (parentNode == null) {
      throw const _DeferredDeltaItemException();
    }
    if (!parentNode.isFolder) {
      throw const OneDriveAuthException('OneDrive 增量变更返回的文件父项不是文件夹。');
    }
    return parentNode.relativePath.isEmpty
        ? itemName
        : '${parentNode.relativePath}/$itemName';
  }

  void _rebuildDescendantPaths(
    Map<String, OneDriveRemoteNode> nodes,
    String itemId,
    String rootId,
  ) {
    final queue = <String>[itemId];
    while (queue.isNotEmpty) {
      final currentId = queue.removeLast();
      final currentNode = nodes[currentId];
      if (currentNode == null) {
        continue;
      }
      final childIds = nodes.values
          .where((node) => node.parentItemId == currentId)
          .map((node) => node.itemId)
          .toList();
      for (final childId in childIds) {
        final childNode = nodes[childId];
        if (childNode == null) {
          continue;
        }
        final relativePath = _buildRelativePath(
          nodes: nodes,
          rootId: rootId,
          parentItemId: childNode.parentItemId,
          itemName: childNode.name,
          itemId: childId,
        );
        nodes[childId] = childNode.copyWith(relativePath: relativePath);
        queue.add(childId);
      }
    }
  }

  void _removeNodeAndDescendants(
    Map<String, OneDriveRemoteNode> nodes,
    String itemId,
  ) {
    final queue = <String>[itemId];
    final toRemove = <String>{};
    while (queue.isNotEmpty) {
      final currentId = queue.removeLast();
      if (!toRemove.add(currentId)) {
        continue;
      }
      final childIds = nodes.values
          .where((node) => node.parentItemId == currentId)
          .map((node) => node.itemId)
          .toList();
      queue.addAll(childIds);
    }
    for (final removeId in toRemove) {
      nodes.remove(removeId);
    }
  }

  Future<Uint8List> _readResponseBytes(HttpClientResponse response) async {
    final chunks = <int>[];
    await for (final data in response) {
      chunks.addAll(data);
    }
    return Uint8List.fromList(chunks);
  }

  String? _graphErrorMessage(String body) {
    try {
      final payload = _decodeJson(body);
      final error = payload['error'];
      if (error is Map) {
        return error['message'] as String? ?? error['code'] as String?;
      }
      return (payload['error_description'] as String?) ??
          (payload['error'] as String?);
    } on FormatException {
      return body.trim().isEmpty ? null : body;
    }
  }

  Map<String, dynamic> _decodeJson(String body) {
    if (body.trim().isEmpty) {
      return <String, dynamic>{};
    }
    return jsonDecode(body) as Map<String, dynamic>;
  }

  bool _isRetryableStatus(int statusCode) {
    return statusCode == 408 ||
        statusCode == 429 ||
        statusCode == 500 ||
        statusCode == 502 ||
        statusCode == 503 ||
        statusCode == 504;
  }

  bool _isRetryableNetworkError(Object error) {
    return error is SocketException ||
        error is HttpException ||
        error is TimeoutException ||
        error is HandshakeException;
  }

  Future<void> _yieldToEventLoop() => Future<void>.delayed(Duration.zero);

  Duration _retryDelay(int attempt, _RawResponse? response) {
    final retryAfter = response?.retryAfter;
    if (retryAfter != null) {
      return retryAfter;
    }

    final seconds = switch (attempt) {
      1 => 2,
      2 => 5,
      _ => 10,
    };
    return Duration(seconds: seconds);
  }

  Duration? _readRetryAfter(HttpClientResponse response) {
    final raw = response.headers.value(HttpHeaders.retryAfterHeader);
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }

    final seconds = int.tryParse(raw.trim());
    if (seconds != null) {
      return Duration(seconds: seconds.clamp(1, 30).toInt());
    }

    final DateTime date;
    try {
      date = HttpDate.parse(raw);
    } on FormatException {
      return null;
    }
    final delay = date.difference(DateTime.now().toUtc());
    if (delay.isNegative) {
      return null;
    }
    return delay > const Duration(seconds: 30)
        ? const Duration(seconds: 30)
        : delay;
  }

  String _networkErrorMessage(Uri uri, Object error) {
    return 'OneDrive 网络连接不稳定，已自动重试但仍失败。'
        '请保持应用在前台，确认网络能访问 ${uri.host} 后再点“立即同步”。'
        '原始错误：$error';
  }
}

class _RawResponse {
  const _RawResponse({
    required this.statusCode,
    required this.body,
    required this.bytes,
    this.retryAfter,
  });

  final int statusCode;
  final String body;
  final Uint8List bytes;
  final Duration? retryAfter;
}

class _DeferredDeltaItemException implements Exception {
  const _DeferredDeltaItemException();
}
