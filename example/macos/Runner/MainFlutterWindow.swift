import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  // Opt-in for headless verification; the native Flutter view remains attached.
  private var isHeadless: Bool {
    ProcessInfo.processInfo.environment["MARIONETTE_HEADLESS"] == "1"
  }

  override func order(_ place: NSWindow.OrderingMode, relativeTo otherWin: Int) {
    if isHeadless && place != .out { return }
    super.order(place, relativeTo: otherWin)
  }

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
    if isHeadless {
      // An offscreen view never receives viewWillAppear, which normally starts
      // FlutterEngine. Start it explicitly without making the NSWindow visible.
      flutterViewController.engine.run(withEntrypoint: nil)
      flutterViewController.view.layoutSubtreeIfNeeded()
    }
  }
}
