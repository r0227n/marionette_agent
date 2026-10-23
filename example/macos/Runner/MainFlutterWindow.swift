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
    #if DEBUG
    let channel = FlutterMethodChannel(
      name: "marionette_agent/native_capture_fixture",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { result(nil); return }
      result(nil)
      DispatchQueue.main.async {
        switch call.method {
        case "panel":
          let panel = NSOpenPanel()
          panel.title = "Native screenshot fixture"
          panel.message = "Verify this macOS file panel appears in the native screenshot."
          let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MarionetteCaptureFixture", isDirectory: true)
          try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
          try? "Dummy capture fixture data.\n".write(to: directory.appendingPathComponent("example.txt"), atomically: true, encoding: .utf8)
          panel.directoryURL = directory
          panel.canChooseFiles = true
          panel.canChooseDirectories = false
          panel.beginSheetModal(for: self) { _ in }
        case "alert":
          let alert = NSAlert()
          alert.messageText = "Native alert fixture"
          alert.informativeText = "This is an AppKit alert, not an OS permission request."
          alert.addButton(withTitle: "OK")
          alert.beginSheetModal(for: self) { _ in }
        case "menu":
          let menu = NSMenu(title: "Native fixture menu")
          menu.addItem(withTitle: "Native menu item", action: nil, keyEquivalent: "")
          menu.addItem(withTitle: "Screenshot includes this menu", action: nil, keyEquivalent: "")
          menu.popUp(positioning: nil, at: NSPoint(x: 220, y: 250), in: self.contentView)
        case "move":
          guard NSScreen.screens.count > 1,
                let screen = NSScreen.screens.first(where: { $0 != self.screen }) else { return }
          self.setFrame(screen.visibleFrame.insetBy(dx: 30, dy: 30), display: true)
          self.makeKeyAndOrderFront(nil)
        default: break
        }
      }
    }
    #endif

    super.awakeFromNib()
    if isHeadless {
      // An offscreen view never receives viewWillAppear, which normally starts
      // FlutterEngine. Start it explicitly without making the NSWindow visible.
      flutterViewController.engine.run(withEntrypoint: nil)
      flutterViewController.view.layoutSubtreeIfNeeded()
    }
  }
}
