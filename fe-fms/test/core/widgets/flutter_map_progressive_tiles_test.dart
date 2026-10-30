// Progressive tiles (#68): a soft preview layer two zooms out is requested
// before the sharp layer, and needs far fewer tiles to cover the screen.
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

void main() {
  testWidgets('preview tiles are requested first, and are few', (tester) async {
    final urls = <Uri>[];
    final client = MockClient((req) async {
      urls.add(req.url);
      return http.Response.bytes(_png, 200,
          headers: {'content-type': 'image/png'});
    });
    // No disk cache: requests reach the fake network in issue order.
    final provider = NetworkTileProvider(
      httpClient: client,
      cachingProvider: const DisabledMapCachingProvider(),
    );

    await tester.pumpWidget(MaterialApp(
      home: FlutterMapWidget(
        center: const GeoPoint(13.4, 121.2),
        zoom: 12,
        tileProvider: provider,
      ),
    ));
    await tester.pump();

    final zooms = urls.map(_z).toList();
    expect(zooms.toSet(), {10, 12}, reason: 'preview is 2 zooms out');
    final preview = zooms.where((z) => z == 10).length;
    final sharp = zooms.where((z) => z == 12).length;
    // All preview tiles before any sharp tile.
    expect(zooms.take(preview), everyElement(10));
    expect(preview, inInclusiveRange(1, 4));
    expect(sharp, greaterThanOrEqualTo(20));

    // Unmount the map so its tile timers aren't left pending.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
