import 'dart:html' as html;
import 'dart:convert';

void downloadWebData(String jsonString, String filename) {
  final bytes = utf8.encode(jsonString);
  final blob = html.Blob([bytes]);
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)
    ..setAttribute("download", filename)
    ..click();
  html.Url.revokeObjectUrl(url);
}
