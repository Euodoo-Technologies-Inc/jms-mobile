import 'dart:async';
import 'dart:io';

import 'package:fms/core/dispatch/dispatch_api_client.dart';

const _timeout = 'The server took too long to respond. Try again.';
const _offline = "Couldn't reach the server. Check your connection and try again.";
const _generic = 'Something went wrong. Try again.';

final _networkText = RegExp(
  'SocketException|ClientException|Failed host lookup|Network is unreachable|Connection refused',
);
final _statusText = RegExp(r'HTTP (\d{3})');

/// Exception text, codes or response bodies that must never reach a user.
final _technicalText = RegExp(
  r'Exception|Error:|HTTP|API Key|null|[{}<>]|\(\d{3}\)',
  caseSensitive: false,
);

/// Turns any caught error into plain copy for a snackbar or error line.
/// Server and data-layer messages pass through only when they already read
/// as copy; everything else maps to a fixed sentence.
String userMessage(Object e) {
  if (e is TimeoutException) return _timeout;
  if (e is SocketException) return _offline;
  if (e is DispatchApiException) {
    // statusCode 0 is the client's own timeout/offline copy.
    if (e.statusCode == 0) return e.message;
    if (e.statusCode >= 500 || e.message == 'Unauthenticated.') {
      return _forStatus(e.statusCode);
    }
    return _plain(e.message) ?? _forStatus(e.statusCode);
  }

  final text = e.toString();
  if (_networkText.hasMatch(text)) return _offline;
  if (text.contains('TimeoutException')) return _timeout;
  final status = _statusText.firstMatch(text);
  if (status != null) return _forStatus(int.parse(status[1]!));
  if (e is Exception) {
    return _plain(text.replaceFirst('Exception: ', '')) ?? _generic;
  }
  return _generic;
}

String? _plain(String message) {
  final m = message.trim();
  if (m.isEmpty || m.length > 160 || _technicalText.hasMatch(m)) return null;
  return m;
}

String _forStatus(int code) {
  if (code == 401) return 'Your session has expired. Log in again.';
  if (code == 403) return "You don't have access to this.";
  if (code == 404) return "We couldn't find that. It may have been removed.";
  if (code == 409) return 'This was already done.';
  if (code == 422) return "Some details aren't valid. Check them and try again.";
  if (code == 429) return 'Too many attempts. Wait a moment and try again.';
  if (code >= 500) return 'The server had a problem. Try again in a moment.';
  return _generic;
}
