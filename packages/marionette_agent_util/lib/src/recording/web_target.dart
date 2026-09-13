/// A Chrome page and an explicitly selected macOS display. One spelling avoids
/// localhost/IP, percent-escape and leading-zero aliases in target identity.
class WebRecordingTarget {
  const WebRecordingTarget(this.display, this.endpoint);
  final String display;
  final Uri endpoint;

  static WebRecordingTarget? parse(String device) {
    final match = RegExp(
      r'^display:([1-9][0-9]{0,2})@(ws://127\.0\.0\.1:([1-9][0-9]{0,4})/devtools/page/[A-Z0-9]+)$',
    ).firstMatch(device);
    if (match == null ||
        match.end != device.length ||
        int.parse(match[3]!) > 65535) {
      return null;
    }
    return WebRecordingTarget(match[1]!, Uri.parse(match[2]!));
  }
}
