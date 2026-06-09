import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_diary/data/diary_storage.dart';
import 'package:love_diary/sync/onedrive/onedrive_auth_service.dart';
import 'package:love_diary/sync/onedrive/onedrive_remote_source.dart';

import 'test_utils.dart';

void main() {
  late Directory tempDirectory;
  late DiaryStorage storage;
  late MemorySecretStore secretStore;
  late OneDriveAuthService authService;
  late OneDriveRemoteSource remoteSource;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp(
      'love_diary_remote_test_',
    );
    secretStore = MemorySecretStore();
    storage = DiaryStorage(
      rootDirectoryPath: tempDirectory.path,
      secretStore: secretStore,
    );
    authService = OneDriveAuthService(storage: storage);
    remoteSource = OneDriveRemoteSource(authService: authService);
  });

  tearDown(() async {
    await deleteTempDirectory(tempDirectory);
  });

  group('OneDriveRemoteSource', () {
    test('persistSnapshot does nothing', () async {
      // persistSnapshot should not throw
      await remoteSource.persistSnapshot([]);
    });

    test('fetchSnapshot throws when no config exists', () async {
      expect(
        () => remoteSource.fetchSnapshot(),
        throwsA(isA<OneDriveAuthException>()),
      );
    });

    test('uploadFile throws when no config exists', () async {
      final testFile = File('${tempDirectory.path}/test.txt');
      await testFile.writeAsString('test content');

      expect(
        () => remoteSource.uploadFile(
          relativePath: 'test.txt',
          absolutePath: testFile.path,
          isBinary: false,
        ),
        throwsA(isA<OneDriveAuthException>()),
      );
    });

    test('downloadFile throws when no config exists', () async {
      final testFile = File('${tempDirectory.path}/test.txt');

      expect(
        () => remoteSource.downloadFile(
          relativePath: 'test.txt',
          targetAbsolutePath: testFile.path,
          isBinary: false,
        ),
        throwsA(isA<OneDriveAuthException>()),
      );
    });

    test('deleteFile throws when no config exists', () async {
      expect(
        () => remoteSource.deleteFile('test.txt'),
        throwsA(isA<OneDriveAuthException>()),
      );
    });
  });
}
