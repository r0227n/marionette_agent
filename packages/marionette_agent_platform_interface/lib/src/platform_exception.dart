/// A safe, structured failure from a platform service.
class PlatformException implements Exception {
  const PlatformException(this.code, this.message, {this.hint});
  final String code, message;
  final String? hint;
  @override
  String toString() => '$code: $message';
}
