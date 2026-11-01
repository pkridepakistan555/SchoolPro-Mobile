import 'admin_printing_stub.dart'
    if (dart.library.html) 'admin_printing_web.dart' as platform;

bool printHtmlDocument(String html) => platform.printHtmlDocument(html);
void downloadCsvFile(String csv, String filename) => platform.downloadCsvFile(csv, filename);
void openDocumentUrl(String url) => platform.openDocumentUrl(url);
