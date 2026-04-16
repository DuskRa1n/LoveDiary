import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../sync_models.dart';
import '../sync_remote_source.dart';
import 'onedrive_auth_service.dart';

class OneDriveRemoteSource implements DiarySyncRemoteSource {
  const OneDriveRemoteSource({required this.authService});

  static const _graphBaseUrl = 'https://graph.microsoft.com/v1.0';
  static const _simpleUploadLimitBytes = 4 * 1024 * 1024;
  static const _uploadChunkSize = 320 * 1024 * 10;

  final OneDriveAuthService authService;

  @override
  Future<void> persistSnapshot(List<LocalSyncFile> localFiles) async {}

  @override
  Future<RemoteSyncSnapshot> fetchSnapshot() async {
    final config = await authService.requireConfig();
    final accessToken = await authService.getValidAccessToken();
    final rootFolder = await _tryGetRemoteFolder(
      accessToken: accessToken,
      relativePath: config.remoteFolder,
    );
    if (rootFolder == null) {
      return const RemoteSyncSnapshot(cursor: null, files: []);
    }

    final files = <RemoteSyncFile>[];
    await _collectFilesRecursively(
      accessToken: accessToken,
      folderId: rootFolder['id'] as String,
      pathPrefix: '',
      sink: files,
    );
    files.sort((a, b) => a.relativePath.compareTo(b.relativePath));
    return RemoteSyncSnapshot(cursor: null, files: files);
  }

  @override
  Future<void> uploadFile({
    required String relativePath,
    required String absolutePath,
    required bool isBinary,
  }) async {
    final config = await authService.requireConfig();
    final accessToken = await authService.getValidAccessToken();
    final localFile = File(absolutePath);
    final stat = await localFile.stat();
    if (stat.size == 0) {
      throw const OneDriveAuthException(
        'OneDrive cannot upload empty files in this sync flow.',
      );
    }

    await _ensureRemoteParentFolders(
      accessToken: accessToken,
      remoteFolder: config.remoteFolder,
      relativePath: relativePath,
    );

    if (stat.size <= _simpleUploadLimitBytes) {
      final bytes = await localFile.readAsBytes();
      await _putFileContent(
        uri: _buildPathUri(config.remoteFolder, relativePath, suffix: 'content'),
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
      headers: {
        HttpHeaders.contentTypeHeader: 'application/json',
      },
      body: utf8.encode(
        jsonEncode({
          'item': {
            '@microsoft.graph.conflictBehavior': 'replace',
          },
        }),
      ),
    );
    final uploadSessionJson = _decodeJson(uploadSessionResponse.body);
    if (uploadSessionResponse.statusCode < 200 ||
        uploadSessionResponse.statusCode >= 300) {
      throw OneDriveAuthException(
        uploadSessionJson['error']?['message'] as String? ??
            'Failed to create OneDrive upload session.',
      );
    }

    final uploadUrl = uploadSessionJson['uploadUrl'] as String;
    final bytes = await localFile.readAsBytes();
    var start = 0;
    while (start < bytes.length) {
      final endExclusive = (start + _uploadChunkSize > bytes.length)
          ? bytes.length
          : start + _uploadChunkSize;
      final chunk = bytes.sublist(start, endExclusive);
      final response = await _sendAbsoluteRequest(
        method: 'PUT',
        uri: Uri.parse(uploadUrl),
        headers: {
          HttpHeaders.contentLengthHeader: chunk.length.toString(),
          HttpHeaders.contentRangeHeader:
              'bytes $start-${endExclusive - 1}/${bytes.length}',
        },
        body: chunk,
      );
      if (response.statusCode != 200 &&
          response.statusCode != 201 &&
          response.statusCode != 202) {
        final payload = _decodeJson(response.body);
        throw OneDriveAuthException(
          payload['error']?['message'] as String? ??
              'OneDrive chunk upload failed.',
        );
      }
      start = endExclusive;
    }
  }

  @override
  Future<void> downloadFile({
    required String relativePath,
    required String targetAbsolutePath,
    required bool isBinary,
  }) async {
    final config = await authService.requireConfig();
    final accessToken = await authService.getValidAccessToken();
    final metadataResponse = await _sendRequest(
      method: 'GET',
      uri: _buildPathUri(config.remoteFolder, relativePath),
      accessToken: accessToken,
    );
    final metadataPayload = _decodeJson(metadataResponse.body);
    if (metadataResponse.statusCode < 200 || metadataResponse.statusCode >= 300) {
      throw OneDriveAuthException(
        metadataPayload['error']?['message'] as String? ??
            'Failed to read OneDrive metadata for $relativePath.',
      );
    }

    final downloadUrl =
        metadataPayload['@microsoft.graph.downloadUrl'] as String?;
    if (downloadUrl == null || downloadUrl.isEmpty) {
      throw OneDriveAuthException(
        'OneDrive did not return a download url for $relativePath.',
      );
    }

    final response = await _sendAbsoluteRequest(
      method: 'GET',
      uri: Uri.parse(downloadUrl),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw OneDriveAuthException(
        'Failed to download $relativePath from OneDrive.',
      );
    }

    final targetFile = File(targetAbsolutePath);
    await targetFile.writeAsBytes(response.bytes, flush: true);
  }

  @override
  Future<void> deleteFile(String relativePath) async {
    final config = await authService.requireConfig();
    final accessToken = await authService.getValidAccessToken();
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
            'Failed to delete $relativePath from OneDrive.',
      );
    }
  }

  Future<void> _collectFilesRecursively({
    required String accessToken,
    required String folderId,
    required String pathPrefix,
    required List<RemoteSyncFile> sink,
  }) async {
    String? nextUrl =
        '$_graphBaseUrl/me/drive/items/$folderId/children?\$select=id,name,eTag,size,lastModifiedDateTime,file,folder';

    while (nextUrl != null) {
      final response = await _sendRequest(
        method: 'GET',
        uri: Uri.parse(nextUrl),
        accessToken: accessToken,
      );
      final payload = _decodeJson(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw OneDriveAuthException(
          payload['error']?['message'] as String? ??
              'Failed to list OneDrive folder children.',
        );
      }

      final items = (payload['value'] as List? ?? const []);
      for (final rawItem in items) {
        final item = rawItem as Map<String, dynamic>;
        final name = item['name'] as String? ?? '';
        if (name.isEmpty) {
          continue;
        }

        final relativePath = pathPrefix.isEmpty ? name : '$pathPrefix/$name';
        if (item['folder'] != null) {
          await _collectFilesRecursively(
            accessToken: accessToken,
            folderId: item['id'] as String,
            pathPrefix: relativePath,
            sink: sink,
          );
          continue;
        }

        final modifiedAt = DateTime.tryParse(
              item['lastModifiedDateTime'] as String? ?? '',
            ) ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final fileFacet = item['file'] as Map<String, dynamic>? ?? const {};
        final hashes = fileFacet['hashes'] as Map<String, dynamic>? ?? const {};
        final fingerprint =
            (hashes['sha1Hash'] as String?) ??
            (hashes['quickXorHash'] as String?) ??
            '${item['size']}:${modifiedAt.millisecondsSinceEpoch}';

        sink.add(
          RemoteSyncFile(
            relativePath: relativePath,
            revision: item['eTag'] as String? ?? item['id'] as String,
            fingerprint: fingerprint,
            modifiedAt: modifiedAt,
            size: (item['size'] as num?)?.toInt() ?? 0,
            isBinary: !relativePath.endsWith('.json'),
          ),
        );
      }

      nextUrl = payload['@odata.nextLink'] as String?;
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
        payload['error']?['message'] as String? ??
            'Failed to read OneDrive folder metadata.',
      );
    }
    return payload;
  }

  Future<void> _ensureRemoteParentFolders({
    required String accessToken,
    required String remoteFolder,
    required String relativePath,
  }) async {
    final segments = [
      remoteFolder,
      ...relativePath.split('/').where((segment) => segment.isNotEmpty).toList()
        ..removeLast(),
    ];

    final approot = await _getApproot(accessToken);
    var parentId = approot['id'] as String;
    for (final segment in segments) {
      parentId = await _ensureFolderChild(
        accessToken: accessToken,
        parentId: parentId,
        folderName: segment,
      );
    }
  }

  Future<Map<String, dynamic>> _getApproot(String accessToken) async {
    final response = await _sendRequest(
      method: 'GET',
      uri: Uri.parse('$_graphBaseUrl/me/drive/special/approot'),
      accessToken: accessToken,
    );
    final payload = _decodeJson(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw OneDriveAuthException(
        payload['error']?['message'] as String? ??
            'Failed to access OneDrive app folder.',
      );
    }
    return payload;
  }

  Future<String> _ensureFolderChild({
    required String accessToken,
    required String parentId,
    required String folderName,
  }) async {
    String? nextUrl =
        '$_graphBaseUrl/me/drive/items/$parentId/children?\$select=id,name,folder';
    while (nextUrl != null) {
      final listResponse = await _sendRequest(
        method: 'GET',
        uri: Uri.parse(nextUrl),
        accessToken: accessToken,
      );
      final listPayload = _decodeJson(listResponse.body);
      if (listResponse.statusCode < 200 || listResponse.statusCode >= 300) {
        throw OneDriveAuthException(
          listPayload['error']?['message'] as String? ??
              'Failed to inspect OneDrive folders.',
        );
      }

      final items = (listPayload['value'] as List? ?? const []);
      for (final rawItem in items) {
        final item = rawItem as Map<String, dynamic>;
        if (item['folder'] != null && item['name'] == folderName) {
          return item['id'] as String;
        }
      }
      nextUrl = listPayload['@odata.nextLink'] as String?;
    }

    final createResponse = await _sendRequest(
      method: 'POST',
      uri: Uri.parse('$_graphBaseUrl/me/drive/items/$parentId/children'),
      accessToken: accessToken,
      headers: {
        HttpHeaders.contentTypeHeader: 'application/json',
      },
      body: utf8.encode(
        jsonEncode({
          'name': folderName,
          'folder': {},
          '@microsoft.graph.conflictBehavior': 'fail',
        }),
      ),
    );
    final createPayload = _decodeJson(createResponse.body);
    if (createResponse.statusCode < 200 || createResponse.statusCode >= 300) {
      throw OneDriveAuthException(
        createPayload['error']?['message'] as String? ??
            'Failed to create OneDrive folder $folderName.',
      );
    }
    return createPayload['id'] as String;
  }

  Uri _buildPathUri(String remoteFolder, String relativePath, {String? suffix}) {
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
        payload['error']?['message'] as String? ??
            'Failed to upload file to OneDrive.',
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
    return _sendAbsoluteRequest(
      method: method,
      uri: uri,
      headers: {
        HttpHeaders.authorizationHeader: 'Bearer $accessToken',
        HttpHeaders.acceptHeader: 'application/json',
        ...?headers,
      },
      body: body,
    );
  }

  Future<_RawResponse> _sendAbsoluteRequest({
    required String method,
    required Uri uri,
    Map<String, String>? headers,
    List<int>? body,
  }) async {
    final client = HttpClient();
    try {
      final request = await client.openUrl(method, uri);
      headers?.forEach(request.headers.set);
      if (body != null && body.isNotEmpty) {
        if (!request.headers.chunkedTransferEncoding) {
          request.contentLength = body.length;
        }
        request.add(body);
      }
      final response = await request.close();
      final bytes = await _readResponseBytes(response);
      return _RawResponse(
        statusCode: response.statusCode,
        body: utf8.decode(bytes, allowMalformed: true),
        bytes: bytes,
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<Uint8List> _readResponseBytes(HttpClientResponse response) async {
    final chunks = <int>[];
    await for (final data in response) {
      chunks.addAll(data);
    }
    return Uint8List.fromList(chunks);
  }

  Map<String, dynamic> _decodeJson(String body) {
    if (body.trim().isEmpty) {
      return <String, dynamic>{};
    }
    return jsonDecode(body) as Map<String, dynamic>;
  }
}

class _RawResponse {
  const _RawResponse({
    required this.statusCode,
    required this.body,
    required this.bytes,
  });

  final int statusCode;
  final String body;
  final Uint8List bytes;
}
