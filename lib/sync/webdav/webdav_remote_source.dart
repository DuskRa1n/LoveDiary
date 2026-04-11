import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:xml/xml.dart';

import '../../data/diary_storage.dart';
import '../sync_models.dart';
import '../sync_remote_source.dart';
import 'webdav_models.dart';

class WebDavSyncException implements Exception {
  const WebDavSyncException(this.message);

  final String message;

  @override
  String toString() => message;
}

class WebDavRemoteSource implements DiarySyncRemoteSource {
  WebDavRemoteSource({required this.storage});

  static const String _remoteIndexFileName = '.love_diary_sync_index.json';

  final DiaryStorage storage;
  final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 20);

  @override
  Future<RemoteSyncSnapshot> fetchSnapshot() async {
    final config = await _requireConfig();
    final indexedSnapshot = await _fetchSnapshotFromIndex(config);
    if (indexedSnapshot != null) {
      return indexedSnapshot;
    }

    final rootUri = _remoteUri(config, '');
    late final List<RemoteSyncFile> files;
    try {
      final rootResponse = await _propfind(
        uri: rootUri,
        config: config,
        depth: 'infinity',
      );
      if (rootResponse.statusCode == 404) {
        return const RemoteSyncSnapshot(cursor: null, files: []);
      }
      _ensureSuccess(rootResponse, allowedStatusCodes: {207});
      files = _parseSnapshotFiles(
        config: config,
        xmlBody: rootResponse.body,
      );
    } on WebDavSyncException catch (error) {
      if (!_shouldFallbackToRecursiveScan(error)) {
        rethrow;
      }
      try {
        files = <RemoteSyncFile>[];
        await _collectRecursively(
          config: config,
          currentRelativePath: '',
          sink: files,
        );
      } on WebDavSyncException catch (recursiveError) {
        if (!_shouldFallbackToEmptySnapshot(recursiveError)) {
          rethrow;
        }
        return const RemoteSyncSnapshot(cursor: null, files: []);
      }
    }

    files.sort((a, b) => a.relativePath.compareTo(b.relativePath));
    return RemoteSyncSnapshot(cursor: null, files: files);
  }

  @override
  Future<void> persistSnapshot(List<LocalSyncFile> localFiles) async {
    final config = await _requireConfig();
    final payload = {
      'schema_version': 1,
      'generated_at': DateTime.now().toUtc().toIso8601String(),
      'files': [
        for (final file in localFiles)
          {
            'relative_path': file.relativePath,
            'fingerprint': file.fingerprint,
            'modified_at': file.modifiedAt.toUtc().toIso8601String(),
            'size': file.size,
            'is_binary': file.isBinary,
          },
      ],
    };
    final response = await _sendRequest(
      method: 'PUT',
      uri: _remoteUri(config, _remoteIndexFileName),
      config: config,
      headers: {
        HttpHeaders.contentTypeHeader: 'application/json; charset=utf-8',
      },
      body: utf8.encode(
        const JsonEncoder.withIndent('  ').convert(payload),
      ),
    );
    _ensureSuccess(response, allowedStatusCodes: {200, 201, 204});
  }

  @override
  Future<void> uploadFile({
    required String relativePath,
    required String absolutePath,
    required bool isBinary,
  }) async {
    final config = await _requireConfig();
    await _ensureRemoteDirectory(config, relativePath);
    final file = File(absolutePath);
    final bytes = await file.readAsBytes();
    final response = await _sendRequest(
      method: 'PUT',
      uri: _remoteUri(config, relativePath),
      config: config,
      body: bytes,
      headers: {
        HttpHeaders.contentTypeHeader: isBinary
            ? 'application/octet-stream'
            : 'application/json; charset=utf-8',
      },
    );
    _ensureSuccess(response, allowedStatusCodes: {200, 201, 204});
  }

  @override
  Future<void> downloadFile({
    required String relativePath,
    required String targetAbsolutePath,
    required bool isBinary,
  }) async {
    final config = await _requireConfig();
    final response = await _sendRequest(
      method: 'GET',
      uri: _remoteUri(config, relativePath),
      config: config,
    );
    _ensureSuccess(response, allowedStatusCodes: {200});

    final file = File(targetAbsolutePath);
    if (!await file.parent.exists()) {
      await file.parent.create(recursive: true);
    }
    await file.writeAsBytes(response.bytes, flush: true);
  }

  @override
  Future<void> deleteFile(String relativePath) async {
    final config = await _requireConfig();
    final response = await _sendRequest(
      method: 'DELETE',
      uri: _remoteUri(config, relativePath),
      config: config,
    );
    if (response.statusCode == 404) {
      return;
    }
    _ensureSuccess(response, allowedStatusCodes: {200, 204});
  }

  Future<void> validateConfig(WebDavSyncConfig config) async {
    final rootResponse = await _propfind(
      uri: _baseUri(config),
      config: config,
      depth: 0,
    );
    if (rootResponse.statusCode == 401 || rootResponse.statusCode == 403) {
      throw const WebDavSyncException('Jianguoyun authentication failed.');
    }
    if (rootResponse.statusCode >= 400) {
      throw WebDavSyncException(
        'WebDAV PROPFIND ${_baseUri(config)} failed: HTTP ${rootResponse.statusCode}',
      );
    }
  }

  Future<WebDavSyncConfig> _requireConfig() async {
    final config = await storage.loadWebDavSyncConfig();
    if (config == null) {
      throw const WebDavSyncException('Jianguoyun sync is not configured.');
    }
    return config;
  }

  List<RemoteSyncFile> _parseSnapshotFiles({
    required WebDavSyncConfig config,
    required String xmlBody,
  }) {
    final files = <RemoteSyncFile>[];
    for (final item in _parsePropfindItems(config, xmlBody)) {
      if (item.isDirectory || _isRemoteIndexPath(item.file.relativePath)) {
        continue;
      }
      files.add(item.file);
    }

    return files;
  }

  Future<void> _collectRecursively({
    required WebDavSyncConfig config,
    required String currentRelativePath,
    required List<RemoteSyncFile> sink,
  }) async {
    final response = await _propfind(
      uri: _remoteUri(config, currentRelativePath),
      config: config,
      depth: 1,
    );
    if (response.statusCode == 404) {
      return;
    }
    _ensureSuccess(response, allowedStatusCodes: {207});

    for (final item in _parsePropfindItems(config, response.body)) {
      if (item.isDirectory) {
        await _collectRecursively(
          config: config,
          currentRelativePath: item.file.relativePath,
          sink: sink,
        );
        continue;
      }
      if (_isRemoteIndexPath(item.file.relativePath)) {
        continue;
      }
      sink.add(item.file);
    }
  }

  Future<RemoteSyncSnapshot?> _fetchSnapshotFromIndex(
    WebDavSyncConfig config,
  ) async {
    final response = await _sendRequest(
      method: 'GET',
      uri: _remoteUri(config, _remoteIndexFileName),
      config: config,
    );
    if (response.statusCode == 404) {
      return null;
    }
    _ensureSuccess(response, allowedStatusCodes: {200});

    final jsonMap = jsonDecode(response.body) as Map<String, dynamic>;
    final rawFiles = jsonMap['files'] as List? ?? const [];
    final files = rawFiles.map((item) {
      final map = item as Map<String, dynamic>;
      final fingerprint = map['fingerprint'] as String;
      final modifiedAt = DateTime.parse(map['modified_at'] as String).toLocal();
      return RemoteSyncFile(
        relativePath: map['relative_path'] as String,
        revision: fingerprint,
        fingerprint: fingerprint,
        modifiedAt: modifiedAt,
        size: map['size'] as int,
        isBinary: map['is_binary'] as bool,
      );
    }).toList()
      ..sort((a, b) => a.relativePath.compareTo(b.relativePath));

    return RemoteSyncSnapshot(cursor: null, files: files);
  }

  List<_ParsedRemoteItem> _parsePropfindItems(
    WebDavSyncConfig config,
    String xmlBody,
  ) {
    final items = <_ParsedRemoteItem>[];
    final document = XmlDocument.parse(xmlBody);
    final responses = document.descendants.whereType<XmlElement>().where(
      (element) => element.name.local == 'response',
    );

    for (final item in responses) {
      final href = item.children.whereType<XmlElement>().firstWhere(
        (element) => element.name.local == 'href',
        orElse: () => XmlElement(XmlName('empty')),
      ).innerText;
      if (href.isEmpty) {
        continue;
      }

      final relativePath = _relativePathFromHref(config, href);
      if (relativePath == null || relativePath.isEmpty) {
        continue;
      }

      final isDirectory = item.descendants.whereType<XmlElement>().any(
        (element) => element.name.local == 'collection',
      );
      final etag = _firstDescendantText(item, 'getetag');
      final contentLength =
          int.tryParse(_firstDescendantText(item, 'getcontentlength')) ?? 0;
      final modifiedAt = _parseHttpDate(
        _firstDescendantText(item, 'getlastmodified'),
      );

      items.add(
        _ParsedRemoteItem(
          isDirectory: isDirectory,
          file: RemoteSyncFile(
            relativePath: relativePath,
            revision: etag.isEmpty ? relativePath : etag,
            fingerprint: etag.isEmpty
                ? '$contentLength:${modifiedAt.millisecondsSinceEpoch}'
                : etag,
            modifiedAt: modifiedAt,
            size: contentLength,
            isBinary: !relativePath.endsWith('.json'),
          ),
        ),
      );
    }

    return items;
  }

  bool _shouldFallbackToRecursiveScan(WebDavSyncException error) {
    return error.message.contains('HTTP 503') &&
        error.message.contains('PROPFIND');
  }

  bool _shouldFallbackToEmptySnapshot(WebDavSyncException error) {
    return error.message.contains('HTTP 503') &&
        error.message.contains('PROPFIND');
  }

  bool _isRemoteIndexPath(String relativePath) {
    return relativePath == _remoteIndexFileName;
  }

  Future<void> _ensureRemoteDirectory(
    WebDavSyncConfig config,
    String relativePath,
  ) async {
    final relativeSegments = relativePath
        .split('/')
        .where((segment) => segment.isNotEmpty)
        .toList();
    if (relativeSegments.isNotEmpty) {
      relativeSegments.removeLast();
    }

    final segments = [
      ...config.remoteFolder.split('/').where((segment) => segment.isNotEmpty),
      ...relativeSegments,
    ];
    if (segments.isEmpty) {
      return;
    }

    var current = '';
    for (final segment in segments) {
      current = current.isEmpty ? segment : '$current/$segment';
      final response = await _sendRequest(
        method: 'MKCOL',
        uri: _baseUri(config).resolve(_encodeSegmentPath(current)),
        config: config,
      );
      if (response.statusCode == 200 ||
          response.statusCode == 201 ||
          response.statusCode == 301 ||
          response.statusCode == 405 ||
          response.statusCode == 409) {
        continue;
      }
      _ensureSuccess(response, allowedStatusCodes: {200, 201, 301, 405, 409});
    }
  }

  Uri _baseUri(WebDavSyncConfig config) {
    final normalized = config.serverUrl.endsWith('/')
        ? config.serverUrl
        : '${config.serverUrl}/';
    return Uri.parse(normalized);
  }

  Uri _remoteUri(WebDavSyncConfig config, String relativePath) {
    final fullPath = [
      ...config.remoteFolder.split('/').where((segment) => segment.isNotEmpty),
      ...relativePath.split('/').where((segment) => segment.isNotEmpty),
    ].join('/');
    if (fullPath.isEmpty) {
      return _baseUri(config);
    }
    return _baseUri(config).resolve(_encodeSegmentPath(fullPath));
  }

  String _encodeSegmentPath(String path) {
    return path
        .split('/')
        .where((segment) => segment.isNotEmpty)
        .map(Uri.encodeComponent)
        .join('/');
  }

  String? _relativePathFromHref(WebDavSyncConfig config, String href) {
    final basePath = _baseUri(config).path;
    final normalizedHref = Uri.decodeFull(Uri.parse(href).path);
    var relative = normalizedHref;
    if (relative.startsWith(basePath)) {
      relative = relative.substring(basePath.length);
    }
    relative = relative.replaceAll(RegExp(r'^/+'), '');

    final folderPrefix = config.remoteFolder.replaceAll(RegExp(r'^/+|/+$'), '');
    if (folderPrefix.isEmpty) {
      return relative.isEmpty ? null : relative;
    }
    if (!relative.startsWith(folderPrefix)) {
      return null;
    }

    final trimmed = relative.substring(folderPrefix.length).replaceAll(
      RegExp(r'^/+'),
      '',
    );
    return trimmed.isEmpty ? null : trimmed;
  }

  Future<_WebDavResponse> _propfind({
    required Uri uri,
    required WebDavSyncConfig config,
    required Object depth,
  }) {
    return _sendRequest(
      method: 'PROPFIND',
      uri: uri,
      config: config,
      headers: {
        'Depth': '$depth',
        HttpHeaders.contentTypeHeader: 'application/xml; charset=utf-8',
      },
      body: utf8.encode(
        '<?xml version="1.0" encoding="utf-8"?>'
        '<d:propfind xmlns:d="DAV:"><d:prop>'
        '<d:resourcetype/><d:getcontentlength/><d:getetag/><d:getlastmodified/>'
        '</d:prop></d:propfind>',
      ),
    );
  }

  Future<_WebDavResponse> _sendRequest({
    required String method,
    required Uri uri,
    required WebDavSyncConfig config,
    Map<String, String>? headers,
    List<int>? body,
  }) async {
    const maxAttempts = 3;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final request = await _client.openUrl(method, uri);
        request.headers.set(
          HttpHeaders.authorizationHeader,
          'Basic ${base64Encode(utf8.encode('${config.username}:${config.password}'))}',
        );
        request.headers.set(HttpHeaders.acceptHeader, '*/*');
        headers?.forEach(request.headers.set);
        if (body != null && body.isNotEmpty) {
          request.add(body);
        }
        final response = await request.close();
        final bytes = await _readResponseBytes(response);
        return _WebDavResponse(
          method: method,
          uri: uri,
          statusCode: response.statusCode,
          body: utf8.decode(bytes, allowMalformed: true),
          bytes: bytes,
        );
      } on SocketException catch (error) {
        if (attempt == maxAttempts) {
          throw WebDavSyncException(
            'WebDAV $method ${uri.toString()} failed: $error',
          );
        }
      } on HttpException catch (error) {
        if (attempt == maxAttempts) {
          throw WebDavSyncException(
            'WebDAV $method ${uri.toString()} failed: $error',
          );
        }
      }

      await Future<void>.delayed(Duration(milliseconds: 250 * attempt));
    }

    throw WebDavSyncException(
      'WebDAV $method ${uri.toString()} failed: unexpected retry exhaustion',
    );
  }

  Future<Uint8List> _readResponseBytes(HttpClientResponse response) async {
    final chunks = <int>[];
    await for (final chunk in response) {
      chunks.addAll(chunk);
    }
    return Uint8List.fromList(chunks);
  }

  void _ensureSuccess(
    _WebDavResponse response, {
    required Set<int> allowedStatusCodes,
  }) {
    if (allowedStatusCodes.contains(response.statusCode)) {
      return;
    }
    throw WebDavSyncException(
      'WebDAV ${response.method} ${response.uri.toString()} failed: HTTP ${response.statusCode}',
    );
  }

  String _firstDescendantText(XmlElement root, String localName) {
    for (final element in root.descendants.whereType<XmlElement>()) {
      if (element.name.local == localName) {
        return element.innerText.trim();
      }
    }
    return '';
  }

  DateTime _parseHttpDate(String value) {
    if (value.isEmpty) {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }
    try {
      return HttpDate.parse(value);
    } catch (_) {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }
  }
}

class _WebDavResponse {
  const _WebDavResponse({
    required this.method,
    required this.uri,
    required this.statusCode,
    required this.body,
    required this.bytes,
  });

  final String method;
  final Uri uri;
  final int statusCode;
  final String body;
  final Uint8List bytes;
}

class _ParsedRemoteItem {
  const _ParsedRemoteItem({
    required this.isDirectory,
    required this.file,
  });

  final bool isDirectory;
  final RemoteSyncFile file;
}
