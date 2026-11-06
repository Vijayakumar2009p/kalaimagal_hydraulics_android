import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../config.dart';

/// The phone could not reach the server (no network, timeout, DNS, TLS...).
class OdooNetworkException implements Exception {
  OdooNetworkException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Odoo answered with an error (wrong password, access rights, validation...).
class OdooException implements Exception {
  OdooException(this.message, {this.name = '', this.code});
  final String message;
  final String name;
  final int? code;

  bool get isSessionExpired => code == 100 || name.contains('SessionExpired');
  bool get isAccessDenied => name.contains('AccessDenied');

  @override
  String toString() => message;
}

/// Minimal JSON-RPC client for the Odoo web routes
/// (`/web/session/authenticate`, `/web/dataset/call_kw`, `/web/database/list`).
/// The same routes are used by Odoo's own web and mobile apps.
class OdooClient {
  OdooClient(String baseUrl) : baseUrl = normalizeUrl(baseUrl);

  final String baseUrl;
  String? sessionId;
  int _requestId = 0;
  final HttpClient _http = HttpClient()
    ..connectionTimeout = const Duration(seconds: 15)
    ..userAgent = AppConfig.userAgent;

  /// "veeveeinfotech.com/odoo/contacts" -> "https://veeveeinfotech.com"
  static String normalizeUrl(String input) {
    var url = input.trim();
    if (url.isEmpty) return url;
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'https://$url';
    }
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return url;
    return Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
    ).toString().replaceAll(RegExp(r'/$'), '');
  }

  void close() => _http.close(force: true);

  Future<dynamic> _rpc(String path, Map<String, dynamic> params) async {
    final uri = Uri.parse('$baseUrl$path');
    final body = jsonEncode({'jsonrpc': '2.0', 'method': 'call', 'params': params, 'id': ++_requestId});
    late final HttpClientResponse response;
    late final String text;
    try {
      final request = await _http.postUrl(uri).timeout(AppConfig.requestTimeout);
      request.headers.contentType = ContentType.json;
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      if (sessionId != null) {
        request.headers.set(HttpHeaders.cookieHeader, 'session_id=$sessionId');
      }
      request.add(utf8.encode(body));
      response = await request.close().timeout(AppConfig.requestTimeout);
      text = await response.transform(utf8.decoder).join().timeout(AppConfig.requestTimeout);
    } on SocketException catch (e) {
      throw OdooNetworkException('No connection to the server (${e.osError?.message ?? e.message}).');
    } on TimeoutException {
      throw OdooNetworkException('The server took too long to answer.');
    } on HandshakeException {
      throw OdooNetworkException('Secure connection failed. Check the server URL.');
    } on HttpException catch (e) {
      throw OdooNetworkException('Connection problem: ${e.message}');
    } on FormatException {
      throw OdooNetworkException('The server sent an unreadable answer.');
    }

    // Read the session cookie from the raw header (Dart's cookie parser is
    // strict and can reject other cookies the website sets).
    final setCookies = response.headers[HttpHeaders.setCookieHeader] ?? const [];
    for (final raw in setCookies) {
      final match = RegExp(r'^\s*session_id=([^;]*)').firstMatch(raw);
      if (match != null && match.group(1)!.isNotEmpty) {
        sessionId = match.group(1);
      }
    }

    // Anything that is not a normal Odoo answer (maintenance page, firewall,
    // Wi-Fi login page...) is treated like "no connection": entries stay
    // waiting and are sent again later.
    if (response.statusCode == 404) {
      throw OdooNetworkException('This address is not an Odoo server (404). Check the server URL.');
    }
    if (response.statusCode >= 500) {
      throw OdooNetworkException('Server error (${response.statusCode}). Try again later.');
    }
    if (response.statusCode != 200) {
      throw OdooNetworkException('Unexpected answer from server (${response.statusCode}). Try again later.');
    }

    final dynamic decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      throw OdooNetworkException('The server did not answer like Odoo. Check the server URL or your Wi-Fi.');
    }
    if (decoded is! Map) {
      throw OdooNetworkException('Unexpected answer from server.');
    }
    final error = decoded['error'];
    if (error is Map) {
      final data = error['data'];
      final name = data is Map ? (data['name'] ?? '').toString() : '';
      var message = data is Map ? (data['message'] ?? '').toString() : '';
      if (message.isEmpty) message = (error['message'] ?? 'Odoo error').toString();
      final code = error['code'] is int ? error['code'] as int : null;
      throw OdooException(message, name: name, code: code);
    }
    return decoded['result'];
  }

  /// Database names on the server. Throws when the server hides the list.
  Future<List<String>> listDatabases() async {
    final result = await _rpc('/web/database/list', {});
    if (result is List) return result.map((e) => e.toString()).toList();
    throw OdooException('Database list not available.');
  }

  /// Logs in and returns Odoo's session info (uid, name, user_context...).
  /// Returns null when the login needs two-factor authentication.
  Future<Map<String, dynamic>?> authenticate(String db, String login, String password) async {
    sessionId = null;
    final result = await _rpc('/web/session/authenticate', {'db': db, 'login': login, 'password': password});
    if (result is! Map) return null;
    final info = Map<String, dynamic>.from(result);
    if (info['uid'] == null || info['uid'] == false) return null;
    return info;
  }

  Future<void> logout() async {
    try {
      await _rpc('/web/session/destroy', {});
    } catch (_) {
      // Logging out locally is enough.
    }
    sessionId = null;
  }

  Future<dynamic> callKw(String model, String method, List<dynamic> args, {Map<String, dynamic>? kwargs}) {
    return _rpc('/web/dataset/call_kw/$model.$method', {
      'model': model,
      'method': method,
      'args': args,
      'kwargs': kwargs ?? <String, dynamic>{},
    });
  }
}
