import 'dart:io';

Future<void> main() async {
  const int port = 8080;
  HttpServer server = await HttpServer.bind(InternetAddress.anyIPv4, port);
  stdout.writeln('Port smoke server listening on http://0.0.0.0:$port');
  stdout.writeln('Open http://127.0.0.1:$port in your browser.');

  await for (HttpRequest request in server) {
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.html
      ..write(_pageFor(request));
    await request.response.close();
  }
}

String _pageFor(HttpRequest request) {
  String host = request.headers.value(HttpHeaders.hostHeader) ?? 'unknown host';
  String path = request.uri.toString();
  String now = DateTime.now().toIso8601String();

  return '''
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <title>Arcane Voice Port Smoke Test</title>
    <style>
      body {
        margin: 0;
        min-height: 100vh;
        display: grid;
        place-items: center;
        font-family: system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
        background: #101820;
        color: #f5f7fb;
      }
      main {
        max-width: 640px;
        padding: 32px;
      }
      h1 {
        margin: 0 0 12px;
        font-size: 36px;
      }
      p {
        margin: 8px 0;
        font-size: 18px;
        line-height: 1.45;
      }
      code {
        color: #7dd3fc;
      }
    </style>
  </head>
  <body>
    <main>
      <h1>It works.</h1>
      <p>Arcane Voice can receive web hits on <code>$host</code>.</p>
      <p>Path: <code>$path</code></p>
      <p>Server time: <code>$now</code></p>
    </main>
  </body>
</html>
''';
}
