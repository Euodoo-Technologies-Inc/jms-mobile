import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fms/core/widgets/flutter_map_widget.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

// A 1×1 PNG: enough for the tile to decode.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=',
);

/// Resolves the tile at [coords] through [provider] and waits for it to decode.
Future<void> _loadTile(NetworkTileProvider provider, TileCoordinates coords) {
  final layer = TileLayer(
    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    tileProvider: provider,
  );
  final done = Completer<void>();
  provider
      .getImageWithCancelLoadingSupport(coords, layer, Completer<void>().future)
      .resolve(ImageConfiguration.empty)
      .addListener(
        ImageStreamListener(
          (_, _) => done.complete(),
          onError: (e, _) => done.completeError(e),
        ),
      );
  return done.future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a tile seen once is served from the disk cache, not the network',
      () async {
    final dir = await Directory.systemTemp.createTemp('fm_tile_cache_test');
    var requests = 0;
    final client = MockClient((_) async {
      requests++;
      // OSM-style headers, but already stale: only the provider's own
      // freshness floor keeps the second load off the network.
      return http.Response.bytes(_png, 200, headers: {
        'content-type': 'image/png',
        'cache-control': 'max-age=0',
        'etag': '"t1"',
        'date': HttpDate.format(DateTime.now()),
      });
    });
    final provider = osmTileProvider(
      httpClient: client,
      cacheDirectory: dir.path,
    );
    const coords = TileCoordinates(1, 2, 3);

    await _loadTile(provider, coords);
    expect(requests, 1);

    // The cache writes on a background isolate; wait for the tile file.
    final cacheDir = Directory('${dir.path}/fm_cache');
    for (var i = 0; i < 100; i++) {
      final files = cacheDir.listSync().where(
        (f) => !f.path.endsWith('sizeMonitor.bin'),
      );
      if (files.isNotEmpty) break;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }

    // Drop the in-memory copy so the next load has to go to the provider.
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();

    await _loadTile(provider, coords);
    expect(requests, 1, reason: 'second load must come from the disk cache');

    await BuiltInMapCachingProvider.getOrCreateInstance().destroy();
    await dir.delete(recursive: true);
  });
}
