import 'dart:convert';
import 'dart:io';

Future<String> fetchMenuApiText(Uri uri) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(uri);
    final response = await request.close();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('HTTP ${response.statusCode}', uri: uri);
    }
    return response.transform(utf8.decoder).join();
  } finally {
    client.close();
  }
}
