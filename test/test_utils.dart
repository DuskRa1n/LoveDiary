import 'dart:io';

Future<void> deleteTempDirectory(Directory directory) async {
  const maxAttempts = 5;

  for (var attempt = 0; attempt < maxAttempts; attempt++) {
    if (!await directory.exists()) {
      return;
    }

    try {
      await directory.delete(recursive: true);
      return;
    } on FileSystemException {
      if (attempt == maxAttempts - 1) {
        rethrow;
      }
      await Future<void>.delayed(Duration(milliseconds: 60 * (attempt + 1)));
    }
  }
}
