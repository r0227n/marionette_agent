import Flutter
import UIKit
#if DEBUG
import Photos
import PhotosUI
#endif

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    #if DEBUG
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "NativeCaptureFixture") else { return }
    let channel = FlutterMethodChannel(name: "marionette.example/native-capture", binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "photoPermission":
        result(nil)
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { _ in }
      case "photoPicker":
        guard let presenter = UIApplication.shared.connectedScenes
          .compactMap({ $0 as? UIWindowScene })
          .flatMap({ $0.windows })
          .first(where: { $0.isKeyWindow })?.rootViewController,
              presenter.presentedViewController == nil else {
          result(FlutterError(code: "unavailable", message: "No idle presenter", details: nil))
          return
        }
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .images
        configuration.selectionLimit = 1
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        presenter.present(picker, animated: true)
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    #endif
  }
}

#if DEBUG
extension AppDelegate: PHPickerViewControllerDelegate {
  func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
    // No user photo is loaded, copied, or logged by this verification fixture.
    picker.dismiss(animated: true)
  }
}
#endif
