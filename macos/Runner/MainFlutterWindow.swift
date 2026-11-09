import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var sleepObserver: NSObjectProtocol?

  deinit {
    if let observer = sleepObserver {
      NSWorkspace.shared.notificationCenter.removeObserver(observer)
    }
  }

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    let power = FlutterMethodChannel(name: "stundehund/power", binaryMessenger: flutterViewController.engine.binaryMessenger)
    sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
    ) { _ in
      power.invokeMethod("suspend", arguments: Int64(Date().timeIntervalSince1970 * 1000))
    }
    let appearance = FlutterMethodChannel(name: "stundehund/appearance", binaryMessenger: flutterViewController.engine.binaryMessenger)
    appearance.setMethodCallHandler { call, result in
      guard call.method == "setIcon" else { result(FlutterMethodNotImplemented); return }
      guard let bytes = call.arguments as? FlutterStandardTypedData,
            let icon = NSImage(data: bytes.data) else {
        result(FlutterError(code: "invalid_icon", message: "Invalid icon data", details: nil))
        return
      }
      NSApp.applicationIconImage = icon
      result(nil)
    }

    super.awakeFromNib()
  }
}
