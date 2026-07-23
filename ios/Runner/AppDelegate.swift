import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var localizationChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    guard let registrar = engineBridge.pluginRegistry.registrar(
      forPlugin: "SudokuLocalizationBridge"
    ) else {
      return
    }

    let channel = FlutterMethodChannel(
      name: "com.devovia.sudoku/localization",
      binaryMessenger: registrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      guard call.method == "getStrings" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard
        let arguments = call.arguments as? [String: Any],
        let keys = arguments["keys"] as? [String]
      else {
        result(FlutterError(
          code: "invalid_arguments",
          message: "Localization keys are missing.",
          details: nil
        ))
        return
      }

      var values: [String: String] = [:]
      for key in keys {
        let localized = NSLocalizedString(
          key,
          tableName: nil,
          bundle: .main,
          value: key,
          comment: ""
        )
        if localized != key {
          values[key] = localized
        }
      }
      result(values)
    }
    localizationChannel = channel
  }
}
