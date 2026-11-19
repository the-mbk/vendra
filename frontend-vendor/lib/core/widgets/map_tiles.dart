// ══════════════════════════════════════════════════════════════
// Vendra App - Map tiles
// The one place the basemap is configured: CARTO raster tiles (Voyager in
// light mode, Dark Matter in dark mode). CARTO serves an "API key
// required" image without the key, so every map uses this layer.
// ══════════════════════════════════════════════════════════════

import 'package:flutter_map/flutter_map.dart';

import '../../config/app_theme.dart';

class MapTiles {
  MapTiles._();

  static const _apiKey = 'cb1_5bea_1_834da8b386e3c4f989f8feca';

  /// Tile URL for the current theme (high-DPI tiles)
  static String get urlTemplate =>
      'https://basemaps.cartocdn.com/rastertiles/${AppColors.isDark ? 'dark_all' : 'voyager'}/{z}/{x}/{y}@2x.png?key=$_apiKey';

  static TileLayer layer() => TileLayer(urlTemplate: urlTemplate, userAgentPackageName: 'com.vendra.app');
}
