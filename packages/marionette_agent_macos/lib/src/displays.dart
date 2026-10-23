import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:marionette_agent_platform_interface/host_support.dart';

final class _Point extends Struct {
  @Double()
  external double x;
  @Double()
  external double y;
}

final class _Size extends Struct {
  @Double()
  external double width;
  @Double()
  external double height;
}

final class _Rect extends Struct {
  external _Point origin;
  external _Size size;
}

/// A display number is the explicit screencapture -D ordinal (main = 1).
/// Keep the complete ordered topology to detect disappearance/reordering.
class MacosDisplay {
  const MacosDisplay(
    this.id,
    this.x,
    this.y,
    this.width,
    this.height,
    this.modeWidth,
    this.modeHeight,
    this.rotation,
  );
  final int id, modeWidth, modeHeight;
  final double x, y, width, height, rotation;
  Map<String, Object> toJson() => {
    'id': id,
    'x': x,
    'y': y,
    'width': width,
    'height': height,
    'modeWidth': modeWidth,
    'modeHeight': modeHeight,
    'rotation': rotation,
  };
}

List<MacosDisplay> activeMacosDisplays() {
  if (!Platform.isMacOS) {
    throw const PlatformException(
      'UNSUPPORTED_CAPABILITY',
      'Native macOS screenshots require macOS',
    );
  }
  try {
    final cg = DynamicLibrary.open(
      '/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics',
    );
    final enumerate = cg
        .lookupFunction<
          Int32 Function(Uint32, Pointer<Uint32>, Pointer<Uint32>),
          int Function(int, Pointer<Uint32>, Pointer<Uint32>)
        >('CGGetActiveDisplayList');
    final bounds = cg
        .lookupFunction<_Rect Function(Uint32), _Rect Function(int)>(
          'CGDisplayBounds',
        );
    final copyMode = cg
        .lookupFunction<
          Pointer<Void> Function(Uint32),
          Pointer<Void> Function(int)
        >('CGDisplayCopyDisplayMode');
    final width = cg
        .lookupFunction<
          Size Function(Pointer<Void>),
          int Function(Pointer<Void>)
        >('CGDisplayModeGetPixelWidth');
    final height = cg
        .lookupFunction<
          Size Function(Pointer<Void>),
          int Function(Pointer<Void>)
        >('CGDisplayModeGetPixelHeight');
    final release = cg
        .lookupFunction<
          Void Function(Pointer<Void>),
          void Function(Pointer<Void>)
        >('CGDisplayModeRelease');
    final rotation = cg
        .lookupFunction<Double Function(Uint32), double Function(int)>(
          'CGDisplayRotation',
        );
    return using((arena) {
      final count = arena<Uint32>();
      final ids = arena<Uint32>(32);
      if (enumerate(32, ids, count) != 0 || count.value >= 32) {
        throw const PlatformException('IO_ERROR', 'Cannot enumerate displays');
      }
      return List.generate(count.value, (index) {
        final id = ids[index];
        final rect = bounds(id);
        final mode = copyMode(id);
        if (mode == nullptr) {
          throw const PlatformException(
            'TARGET_NOT_FOUND',
            'Display mode disappeared',
          );
        }
        try {
          return MacosDisplay(
            id,
            rect.origin.x,
            rect.origin.y,
            rect.size.width,
            rect.size.height,
            width(mode),
            height(mode),
            rotation(id),
          );
        } finally {
          release(mode);
        }
      });
    });
  } on PlatformException {
    rethrow;
  } catch (_) {
    throw const PlatformException(
      'UNSUPPORTED_CAPABILITY',
      'macOS display APIs are unavailable',
    );
  }
}
