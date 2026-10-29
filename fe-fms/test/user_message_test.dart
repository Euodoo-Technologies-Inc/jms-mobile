import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fms/core/dispatch/dispatch_api_client.dart';
import 'package:fms/core/utils/user_message.dart';

void main() {
  DispatchApiException api(int code, String message) =>
      DispatchApiException(statusCode: code, message: message);

  test('timeout', () {
    expect(userMessage(TimeoutException('x')), contains('took too long'));
    expect(
      userMessage(Exception('TimeoutException after 0:00:15')),
      contains('took too long'),
    );
  });

  test('no network', () {
    const offline = "Couldn't reach the server. Check your connection and try again.";
    expect(userMessage(const SocketException('Failed host lookup')), offline);
    expect(
      userMessage(Exception('ClientException with SocketException: refused')),
      offline,
    );
  });

  test('401', () {
    expect(userMessage(Exception('HTTP 401: {"Message":"Unauthorized"}')),
        'Your session has expired. Log in again.');
    expect(userMessage(api(401, 'Unauthenticated.')),
        'Your session has expired. Log in again.');
    // Login keeps the server's own wording.
    expect(userMessage(api(401, 'Invalid credentials')), 'Invalid credentials');
  });

  test('422', () {
    expect(userMessage(api(422, 'Invalid or expired code')),
        'Invalid or expired code');
    expect(userMessage(Exception('HTTP 422: {"errors":{}}')),
        "Some details aren't valid. Check them and try again.");
  });

  test('500', () {
    const server = 'The server had a problem. Try again in a moment.';
    expect(userMessage(Exception('HTTP 500: <html>Server Error</html>')), server);
    expect(userMessage(api(500, 'Server Error')), server);
  });

  test('data-layer copy passes through, technical text does not', () {
    expect(userMessage(Exception('Job Not Found')), 'Job Not Found');
    expect(userMessage(Exception('API Key not found')),
        'Something went wrong. Try again.');
    expect(userMessage(Exception('Failed to load profile (500)')),
        'Something went wrong. Try again.');
    expect(userMessage(StateError('Bad state')), 'Something went wrong. Try again.');
  });
}
