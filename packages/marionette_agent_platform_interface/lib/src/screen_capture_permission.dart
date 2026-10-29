import 'dart:ffi';

import 'platform_exception.dart';

/// Read-only TCC preflight. The public API cannot distinguish denial from a
/// permission that has never been requested. Never request or modify access.
bool screenCaptureAllowed() {
  try {
    return DynamicLibrary.open(
      '/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics',
    ).lookupFunction<Bool Function(), bool Function()>(
      'CGPreflightScreenCaptureAccess',
    )();
  } catch (_) {
    throw const PlatformException(
      'UNSUPPORTED_CAPABILITY',
      'macOS screen recording permission API is unavailable',
    );
  }
}
