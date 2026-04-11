import 'sync_models.dart';

abstract class DiarySyncRemoteSource {
  Future<RemoteSyncSnapshot> fetchSnapshot();

  Future<void> persistSnapshot(List<LocalSyncFile> localFiles) async {}

  Future<void> uploadFile({
    required String relativePath,
    required String absolutePath,
    required bool isBinary,
  });

  Future<void> downloadFile({
    required String relativePath,
    required String targetAbsolutePath,
    required bool isBinary,
  });

  Future<void> deleteFile(String relativePath);
}
