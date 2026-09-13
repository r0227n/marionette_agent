import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:marionette_flutter/marionette_flutter.dart';

/// Debug-only optional adapter contract. Captures the same physical layer space
/// as binding 0.6.0, without its configurable resize or failed-view filtering.
void registerMappedScreenshot() {
  registerMarionetteExtension(
    name: 'marionette_agent.captureMappedScreenshot',
    callback: (_) async {
      const unsupported = MarionetteExtensionResult.success({
        'supported': false,
      });
      final views = WidgetsBinding.instance.renderViews.toList();
      if (views.length != 1) return unsupported;
      final renderView = views.single;
      final view = renderView.flutterView;
      final size = view.physicalSize;
      final ratio = view.devicePixelRatio;
      // A dirty layer may belong to a previous layout. Let the caller retry
      // explicitly after taking a fresh snapshot instead of forcing a frame.
      // ignore: invalid_use_of_protected_member
      final layer = renderView.layer;
      if (layer == null ||
          renderView.debugNeedsPaint ||
          size.isEmpty ||
          !ratio.isFinite ||
          ratio <= 0 ||
          renderView.size != size / ratio ||
          renderView.configuration.devicePixelRatio != ratio) {
        return unsupported;
      }
      final builder = ui.SceneBuilder();
      layer.addToScene(builder);
      final scene = builder.build();
      ui.Image? image;
      try {
        image = await scene.toImage(size.width.ceil(), size.height.ceil());
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        if (bytes == null ||
            view.physicalSize != size ||
            view.devicePixelRatio != ratio ||
            renderView.size != size / ratio ||
            WidgetsBinding.instance.renderViews.length != 1 ||
            !identical(
              WidgetsBinding.instance.renderViews.single,
              renderView,
            )) {
          return unsupported;
        }
        return MarionetteExtensionResult.success({
          'supported': true,
          'screenshots': [
            base64Encode(
              bytes.buffer.asUint8List(
                bytes.offsetInBytes,
                bytes.lengthInBytes,
              ),
            ),
          ],
          'geometry': {
            'version': 1,
            'viewCount': 1,
            'viewId': view.viewId.toString(),
            'originX': 0,
            'originY': 0,
            'rotation': 0,
            'pixelWidth': image.width,
            'pixelHeight': image.height,
            'logicalWidth': size.width / ratio,
            'logicalHeight': size.height / ratio,
          },
        });
      } finally {
        image?.dispose();
        scene.dispose();
      }
    },
  );
}
