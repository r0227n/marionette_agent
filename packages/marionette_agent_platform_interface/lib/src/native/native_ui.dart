/// Device-screen coordinates: iOS points, Android physical pixels.
class NativeBounds {
  const NativeBounds(this.x, this.y, this.width, this.height);
  final double x, y, width, height;
  bool get tappable =>
      [x, y, width, height].every((v) => v.isFinite) &&
      x >= 0 &&
      y >= 0 &&
      width > 0 &&
      height > 0;
  Map<String, Object?> toJson() => {
    'x': x,
    'y': y,
    'width': width,
    'height': height,
  };
}

/// Normalized accessibility observation; platform wire formats stay in adapters.
class NativeElement {
  const NativeElement({
    required this.type,
    required this.bounds,
    required this.enabled,
    this.text,
    this.identifier,
    this.value,
    this.package,
  });
  final String type;
  final String? text, identifier, value, package;
  final NativeBounds bounds;
  final bool enabled;
  bool get tappable => enabled && bounds.tappable;
  Map<String, Object?> toJson() => {
    'type': type,
    'text': text,
    'identifier': identifier,
    'value': value,
    'package': package,
    'enabled': enabled,
    'bounds': bounds.toJson(),
  };
}

/// Native accessibility and input, independent of a Flutter VM connection.
abstract interface class NativeUiBackend {
  Future<List<NativeElement>> inspect(String device, DateTime deadline);
  Future<void> tap(String device, double x, double y, DateTime deadline);
  Future<void> swipe(
    String device,
    double startX,
    double startY,
    double endX,
    double endY,
    DateTime deadline,
  );
}
