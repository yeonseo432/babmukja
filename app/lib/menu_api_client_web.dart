// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;

Future<String> fetchMenuApiText(Uri uri) async {
  final response = await html.HttpRequest.request(uri.toString());
  final status = response.status ?? 0;
  if (status < 200 || status >= 300) {
    throw Exception('HTTP $status');
  }
  return response.responseText ?? '';
}
