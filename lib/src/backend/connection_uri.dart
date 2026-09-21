import '../protocol/protocol.dart';

/// Keep auth path/query and normalize HTTP(S) URLs to a single WS(S)/ws suffix.
Uri normalizeUri(String input) {
  final uri = Uri.tryParse(input);
  if (uri == null ||
      !['http', 'https', 'ws', 'wss'].contains(uri.scheme) ||
      uri.host.isEmpty ||
      uri.hasFragment) {
    invalid('Expected an HTTP(S) or WS(S) VM Service URI');
  }
  var path = uri.path;
  while (path.endsWith('/')) {
    path = path.substring(0, path.length - 1);
  }
  if (!path.endsWith('/ws')) path = '$path/ws';
  return uri.replace(
    scheme: switch (uri.scheme) {
      'http' => 'ws',
      'https' => 'wss',
      _ => uri.scheme,
    },
    path: path,
  );
}

/// Expose only host/port for health checks and strip userinfo/path/query.

String redactUri(Uri uri) => Uri(
  scheme: uri.scheme,
  host: uri.host,
  port: uri.hasPort ? uri.port : null,
  path: '/<redacted>',
).toString();
