/// An owned encoding session. Cancellation affects only this encoder's work.
abstract interface class VideoEncoder {
  List<String> get h264Arguments;
  bool get isRunning;
  Future<void> get ended;
  Future<void> run(List<String> arguments, DateTime deadline);
  Future<void> abort();
}
