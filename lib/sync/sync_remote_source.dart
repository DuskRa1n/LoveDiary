import 'sync_models.dart';

typedef SyncProgressCallback = void Function(double progress, String label);
typedef SyncCancellationCheck = void Function();

abstract class DiarySyncRemoteSource {
  Future<RemoteSyncSnapshot> fetchSnapshot({
    SyncState? baseline,
    SyncProgressCallback? onProgress,
    SyncCancellationCheck? checkCancelled,
  });

  Future<void> persistSnapshot(List<LocalSyncFile> localFiles) async {}

  Future<void> uploadFile({
    required String relativePath,
    required String absolutePath,
    required bool isBinary,
    SyncCancellationCheck? checkCancelled,
  });

  Future<void> downloadFile({
    required String relativePath,
    required String targetAbsolutePath,
    required bool isBinary,
    SyncCancellationCheck? checkCancelled,
  });

  Future<void> deleteFile(String relativePath, {SyncCancellationCheck? checkCancelled});
}
