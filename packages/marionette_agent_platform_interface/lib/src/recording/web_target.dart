/// One explicitly selected Chromium page; no OS display capture.
class WebRecordingTarget {
  const WebRecordingTarget(this.endpoint);
  final Uri endpoint;
  static WebRecordingTarget? parse(String device) {
    final match = RegExp(
      r'^ws://127\.0\.0\.1:([1-9][0-9]{0,4})/devtools/page/[A-Z0-9]+$',
    ).firstMatch(device);
    if (match == null ||
        match.end != device.length ||
        int.parse(match[1]!) > 65535) {
      return null;
    }
    return WebRecordingTarget(Uri.parse(device));
  }
}
