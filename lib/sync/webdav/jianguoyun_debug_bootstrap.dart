import 'webdav_models.dart';

// Local debug-only bootstrap config.
// Keep this disabled in version control. If you need it locally, fill the
// placeholders below on your own machine without pushing the credentials.
const kDebugJianguoyunBootstrapEnabled = false;

const kDebugJianguoyunBootstrapConfig = WebDavSyncConfig(
  serverUrl: 'https://dav.jianguoyun.com/dav/',
  username: '',
  password: '',
  remoteFolder: 'love_diary',
);
