import 'dart:html' as html;
import 'dart:convert';

bool printHtmlDocument(String htmlText) {
  final dynamic win = html.window.open('', '_blank');
  if (win == null) return false;
  win.document.open();
  win.document.write(htmlText);
  win.document.close();
  win.onLoad.first.then((_) => win.print());
  return true;
}

void downloadCsvFile(String csv, String filename) {
  final blob = html.Blob([utf8.encode(csv)], 'text/csv;charset=utf-8');
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: url)..download = filename..click();
  html.Url.revokeObjectUrl(url);
}

void openDocumentUrl(String url) {
  if (url.startsWith('https://') || url.startsWith('http://')) {
    html.window.open(url, '_blank');
  }
}
