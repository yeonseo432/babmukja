import 'dart:async';

Future<String> fetchMenuApiText(Uri uri) {
  return Future.error(
    UnsupportedError('HTTP is not available on this platform'),
  );
}
