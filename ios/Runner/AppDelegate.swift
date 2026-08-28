import Flutter
import UIKit

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

    let channel = FlutterMethodChannel(
      name: "bearfuel/external_url",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      guard call.method == "openUrl",
            let arguments = call.arguments as? [String: Any],
            let rawUrl = arguments["url"] as? String,
            let url = URL(string: rawUrl),
            let scheme = url.scheme?.lowercased(),
            scheme == "http" || scheme == "https" else {
        result(false)
        return
      }

      UIApplication.shared.open(url, options: [:]) { opened in
        result(opened)
      }
    }
  }
}
