// Tile queue (#70): on a slow network with OSM's 2 connections, the
// fit-to-bounds glide requests nothing for its intermediate frames, the final
// view's preview tiles come before its sharp tiles, and a tile pruned before
// it started never takes a connection slot.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fms/core/models/geo.dart';
import 'package:fms/core/widgets/flutter_map_widget.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

// A 1×1 PNG: enough for the tile to decode.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=',
);

/// The `{z}` of an OSM tile URL.
int _z(Uri u) => int.parse(u.pathSegments[0]);

/// A tile server that answers only when the test tells it to.
class _SlowNet {
  final urls = <Uri>[];
  final _open = <Completer<http.Response>>[];

  late final client = MockClient((req) {
    urls.add(req.url);
    final c = Completer<http.Response>();
    _open.add(c);
    return c.future;
  });

  int get inFlight => _open.length;

  /// Answer every open request.
  void serve() {
    for (final c in _open) {
      c.complete(
        http.Response.bytes(_png, 200, headers: {'content-type': 'image/png'}),
      );
    }
    _open.clear();
  }

  /// Serve until nothing more is asked for.
  Future<void> drain(WidgetTester tester) async {
    do {
      serve();
      await tester.pump();
    } while (_open.isNotEmpty);
  }
}

Widget _map(_SlowNet net, {GeoBounds? fit}) => MaterialApp(
  home: FlutterMapWidget(
    center: const GeoPoint(13.4, 121.2),
    zoom: 12,
    fitBounds: fit,
    tileProvider: NetworkTileProvider(
      httpClient: TileQueueClient(net.client),
      // No disk cache: requests reach the fake network in issue order.
      cachingProvider: const DisabledMapCachingProvider(),
    ),
  ),
);

// Calapan down to the south of Mindoro: ~180 km north–south.
const _farRoute = GeoBounds(
  southWest: GeoPoint(12.2, 120.9),
  northEast: GeoPoint(13.4, 121.5),
);

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 1));
}

void main() {
  // Decoded tiles outlive a test in Flutter's image cache; start each cold.
  setUp(() => PaintingBinding.instance.imageCache
    ..clear()
    ..clearLiveImages());

  testWidgets('two slots at a time; nothing mid-glide; final preview first',
      (tester) async {
    final net = _SlowNet();
    await tester.pumpWidget(_map(net));
    await tester.pump();
    expect(net.inFlight, 2, reason: 'only 2 downloads at once');
    await net.drain(tester);
    final cityTiles = net.urls.length;
    expect(cityTiles, greaterThan(20));

    // Open a far job: the camera glides out for 600 ms.
    await tester.pumpWidget(_map(net, fit: _farRoute));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(net.urls.length, cityTiles,
        reason: 'no tile requested for an intermediate frame');
    await tester.pump(const Duration(milliseconds: 150));
    expect(net.inFlight, 2, reason: 'the final view starts loading');

    await net.drain(tester);
    final zooms = net.urls.skip(cityTiles).map(_z).toList();
    final sharp = zooms.reduce((a, b) => a > b ? a : b);
    expect(sharp, lessThan(10), reason: 'zoomed out from 12 to a 180 km view');
    expect(zooms.toSet(), {sharp - 2, sharp},
        reason: 'only the final view: its preview and its sharp tiles');
    final preview = zooms.where((z) => z == sharp - 2).length;
    expect(preview, inInclusiveRange(1, 4));
    expect(zooms.take(preview), everyElement(sharp - 2),
        reason: 'every preview tile before any sharp tile');

    await _unmount(tester);
  });

  testWidgets('a tile pruned before it started never takes a slot',
      (tester) async {
    final net = _SlowNet();
    await tester.pumpWidget(_map(net));
    await tester.pump();
    // 2 city tiles are in flight; 20+ more wait in the queue. Glide away
    // before any of them starts.
    expect(net.inFlight, 2);
    await tester.pumpWidget(_map(net, fit: _farRoute));
    await tester.pumpAndSettle();
    expect(net.urls.length, 2, reason: 'the slow slots are still held');

    await net.drain(tester);
    final zooms = net.urls.skip(2).map(_z).toSet();
    expect(zooms, isNot(contains(10)), reason: 'queued city previews dropped');
    expect(zooms, isNot(contains(12)), reason: 'queued city tiles dropped');

    await _unmount(tester);
  });
}
