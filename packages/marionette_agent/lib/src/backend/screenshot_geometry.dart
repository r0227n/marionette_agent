import '../protocol/protocol.dart';

/// Geometry comes from a capture provider, never inferred from element bounds.
class ScreenshotGeometry {
  ScreenshotGeometry._(
    this.viewId,
    this.width,
    this.height,
    this.logicalWidth,
    this.logicalHeight,
  );
  final String viewId;
  final int width, height;
  final double logicalWidth, logicalHeight;

  Json toJson() => {
    'version': 1,
    'viewCount': 1,
    'viewId': viewId,
    'rotation': 0,
    'originX': 0,
    'originY': 0,
    'pixelWidth': width,
    'pixelHeight': height,
    'logicalWidth': logicalWidth,
    'logicalHeight': logicalHeight,
  };

  static ScreenshotGeometry decode(Object? raw) {
    Never unsupported() => throw const AgentError(
      'UNSUPPORTED_CAPABILITY',
      'Screenshot requires verified single-view, unrotated geometry v1',
    );
    if (raw is! Map ||
        raw['version'] != 1 ||
        raw['viewCount'] != 1 ||
        raw['viewId'] is! String ||
        (raw['viewId'] as String).isEmpty ||
        raw['rotation'] != 0 ||
        raw['originX'] != 0 ||
        raw['originY'] != 0) {
      unsupported();
    }
    final width = raw['pixelWidth'];
    final height = raw['pixelHeight'];
    final logicalWidth = raw['logicalWidth'];
    final logicalHeight = raw['logicalHeight'];
    if (width is! int ||
        height is! int ||
        width <= 0 ||
        height <= 0 ||
        logicalWidth is! num ||
        logicalHeight is! num ||
        !logicalWidth.isFinite ||
        !logicalHeight.isFinite ||
        logicalWidth <= 0 ||
        logicalHeight <= 0) {
      unsupported();
    }
    return ScreenshotGeometry._(
      raw['viewId'] as String,
      width,
      height,
      logicalWidth.toDouble(),
      logicalHeight.toDouble(),
    );
  }
}
