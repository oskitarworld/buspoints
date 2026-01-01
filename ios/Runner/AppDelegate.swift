import UIKit
import Flutter
import GoogleMaps

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GMSServices.provideAPIKey("AIzaSyBaWj1i61snBGYrVhiRnbbf2M_cYbyBITY")
    GeneratedPluginRegistrant.register(with: self)

    // Register MethodChannel to open native Street View
    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(name: "com.app.buspoints/streetview", binaryMessenger: controller.binaryMessenger)
      channel.setMethodCallHandler { (call: FlutterMethodCall, result: @escaping FlutterResult) in
        if call.method == "openStreetView" {
          guard let args = call.arguments as? [String: Any],
                let lat = args["lat"] as? Double,
                let lng = args["lng"] as? Double else {
            result(FlutterError(code: "INVALID_ARGS", message: "Missing lat/lng", details: nil))
            return
          }
          DispatchQueue.main.async {
            let svc = StreetViewController(lat: lat, lng: lng)
            svc.modalPresentationStyle = .fullScreen
            controller.present(svc, animated: true, completion: nil)
          }
          result(nil)
        } else {
          result(FlutterMethodNotImplemented)
        }
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
