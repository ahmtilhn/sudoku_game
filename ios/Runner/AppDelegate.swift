import Flutter
import GameKit
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, GKGameCenterControllerDelegate {
  private var localizationChannel: FlutterMethodChannel?
  private var gameServicesChannel: FlutterMethodChannel?
  private var pendingAuthenticationResult: FlutterResult?

  private var isGameCenterConfigured: Bool {
    guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return false }
    return !bundleIdentifier.hasPrefix("com.example.")
  }

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    guard let registrar = engineBridge.pluginRegistry.registrar(
      forPlugin: "SudokuPlatformBridges"
    ) else {
      return
    }

    configureLocalizationChannel(messenger: registrar.messenger())
    configureGameServicesChannel(messenger: registrar.messenger())
  }

  private func configureLocalizationChannel(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "com.devovia.sudoku/localization",
      binaryMessenger: messenger
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

  private func configureGameServicesChannel(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "com.devoviastudio.sudoku/game_services",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterError(code: "bridge_unavailable", message: nil, details: nil))
        return
      }

      switch call.method {
      case "isConfigured":
        result(self.isGameCenterConfigured)
      case "isAuthenticated":
        result(GKLocalPlayer.local.isAuthenticated)
      case "authenticate":
        self.authenticate(result: result)
      case "getLocalPlayer":
        self.getLocalPlayer(result: result)
      case "loadFriends":
        self.loadFriends(result: result)
      case "loadRecentPlayers":
        self.loadRecentPlayers(result: result)
      case "showFriends":
        self.showDashboard(state: .localPlayerFriendsList, result: result)
      case "showPlayerProfile":
        let arguments = call.arguments as? [String: Any]
        self.showPlayerProfile(
          playerID: arguments?["playerId"] as? String,
          result: result
        )
      case "showAchievements":
        self.showDashboard(state: .achievements, result: result)
      case "showLeaderboard":
        let arguments = call.arguments as? [String: Any]
        self.showLeaderboard(
          leaderboardID: arguments?["leaderboardId"] as? String,
          result: result
        )
      case "submitScore":
        let arguments = call.arguments as? [String: Any]
        self.submitScore(
          leaderboardID: arguments?["leaderboardId"] as? String,
          score: (arguments?["score"] as? NSNumber)?.intValue,
          result: result
        )
      case "unlockAchievement":
        let arguments = call.arguments as? [String: Any]
        self.unlockAchievement(
          achievementID: arguments?["achievementId"] as? String,
          result: result
        )
      case "requestIdentityVerification":
        self.requestIdentityVerification(result: result)
      case "requestServerAuthCode":
        result(FlutterError(
          code: "unsupported_platform",
          message: "Use requestIdentityVerification on Game Center.",
          details: nil
        ))
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    gameServicesChannel = channel
  }

  private func ensureConfigured(result: FlutterResult) -> Bool {
    guard isGameCenterConfigured else {
      result(FlutterError(
        code: "not_configured",
        message: "Replace the iOS bundle ID and enable Game Center in App Store Connect.",
        details: nil
      ))
      return false
    }
    return true
  }

  private func ensureAuthenticated(result: FlutterResult) -> Bool {
    guard ensureConfigured(result: result) else { return false }
    guard GKLocalPlayer.local.isAuthenticated else {
      result(FlutterError(
        code: "not_authenticated",
        message: "Sign in to Game Center first.",
        details: nil
      ))
      return false
    }
    return true
  }

  private func authenticate(result: @escaping FlutterResult) {
    guard ensureConfigured(result: result) else { return }
    guard pendingAuthenticationResult == nil else {
      result(FlutterError(
        code: "authentication_in_progress",
        message: "Game Center authentication is already in progress.",
        details: nil
      ))
      return
    }

    if GKLocalPlayer.local.isAuthenticated {
      result(true)
      return
    }

    pendingAuthenticationResult = result
    GKLocalPlayer.local.authenticateHandler = { [weak self] viewController, error in
      guard let self else { return }
      DispatchQueue.main.async {
        if let viewController {
          guard let presenter = self.topViewController() else {
            self.completeAuthentication(
              error: FlutterError(
                code: "presentation_failed",
                message: "Unable to present the Game Center sign-in screen.",
                details: nil
              )
            )
            return
          }
          presenter.present(viewController, animated: true)
          return
        }

        if let error {
          self.completeAuthentication(
            error: FlutterError(
              code: "authentication_failed",
              message: error.localizedDescription,
              details: nil
            )
          )
          return
        }

        self.completeAuthentication(value: GKLocalPlayer.local.isAuthenticated)
      }
    }
  }

  private func completeAuthentication(value: Bool? = nil, error: FlutterError? = nil) {
    guard let result = pendingAuthenticationResult else { return }
    pendingAuthenticationResult = nil
    if let error {
      result(error)
    } else {
      result(value ?? false)
    }
  }

  private func getLocalPlayer(result: FlutterResult) {
    guard ensureAuthenticated(result: result) else { return }
    let player = GKLocalPlayer.local
    result([
      "platform": "game_center",
      "playerId": player.gamePlayerID,
      "displayName": player.displayName,
      "alias": player.alias,
    ])
  }

  private func loadFriends(result: @escaping FlutterResult) {
    guard ensureAuthenticated(result: result) else { return }
    GKLocalPlayer.local.loadFriends { players, error in
      DispatchQueue.main.async {
        if let error {
          result(FlutterError(
            code: "friends_unavailable",
            message: error.localizedDescription,
            details: nil
          ))
          return
        }
        result((players ?? []).map(self.playerMap))
      }
    }
  }

  private func loadRecentPlayers(result: @escaping FlutterResult) {
    guard ensureAuthenticated(result: result) else { return }
    GKLocalPlayer.local.loadRecentPlayers { players, error in
      DispatchQueue.main.async {
        if let error {
          result(FlutterError(
            code: "recent_players_unavailable",
            message: error.localizedDescription,
            details: nil
          ))
          return
        }
        result((players ?? []).map(self.playerMap))
      }
    }
  }

  private func playerMap(_ player: GKPlayer) -> [String: Any] {
    return [
      "platform": "game_center",
      "playerId": player.gamePlayerID,
      "displayName": player.displayName,
      "alias": player.alias,
    ]
  }

  private func showPlayerProfile(playerID: String?, result: @escaping FlutterResult) {
    guard ensureAuthenticated(result: result) else { return }
    guard let playerID, !playerID.isEmpty else {
      result(FlutterError(code: "invalid_player", message: "A player ID is required.", details: nil))
      return
    }

    GKPlayer.loadPlayers(forIdentifiers: [playerID]) { [weak self] players, error in
      guard let self else { return }
      DispatchQueue.main.async {
        if let error {
          result(FlutterError(code: "profile_unavailable", message: error.localizedDescription, details: nil))
          return
        }
        guard let player = players?.first else {
          result(FlutterError(code: "player_not_found", message: nil, details: nil))
          return
        }
        let controller = GKGameCenterViewController(player: player)
        self.presentGameCenter(controller, result: result)
      }
    }
  }

  private func showLeaderboard(leaderboardID: String?, result: FlutterResult) {
    guard ensureAuthenticated(result: result) else { return }
    let resolvedID = nonPlaceholder(
      leaderboardID ?? Bundle.main.object(forInfoDictionaryKey: "SudokuLeaderboardGlobalRating") as? String
    )
    let controller: GKGameCenterViewController
    if let resolvedID {
      controller = GKGameCenterViewController(
        leaderboardID: resolvedID,
        playerScope: .global,
        timeScope: .allTime
      )
    } else {
      controller = GKGameCenterViewController(state: .leaderboards)
    }
    presentGameCenter(controller, result: result)
  }

  private func showDashboard(state: GKGameCenterViewControllerState, result: FlutterResult) {
    guard ensureAuthenticated(result: result) else { return }
    presentGameCenter(GKGameCenterViewController(state: state), result: result)
  }

  private func presentGameCenter(_ controller: GKGameCenterViewController, result: FlutterResult) {
    guard let presenter = topViewController() else {
      result(FlutterError(code: "presentation_failed", message: nil, details: nil))
      return
    }
    controller.gameCenterDelegate = self
    presenter.present(controller, animated: true)
    result(true)
  }

  func gameCenterViewControllerDidFinish(_ gameCenterViewController: GKGameCenterViewController) {
    gameCenterViewController.dismiss(animated: true)
  }

  private func submitScore(
    leaderboardID: String?,
    score: Int?,
    result: @escaping FlutterResult
  ) {
    guard ensureAuthenticated(result: result) else { return }
    guard let score else {
      result(FlutterError(code: "invalid_score", message: "A score is required.", details: nil))
      return
    }
    guard let resolvedID = nonPlaceholder(
      leaderboardID ?? Bundle.main.object(forInfoDictionaryKey: "SudokuLeaderboardGlobalRating") as? String
    ) else {
      result(FlutterError(code: "not_configured", message: "Replace the leaderboard ID placeholder.", details: nil))
      return
    }

    GKLeaderboard.submitScore(
      score,
      context: 0,
      player: GKLocalPlayer.local,
      leaderboardIDs: [resolvedID]
    ) { error in
      DispatchQueue.main.async {
        if let error {
          result(FlutterError(code: "score_submit_failed", message: error.localizedDescription, details: nil))
        } else {
          result(true)
        }
      }
    }
  }

  private func unlockAchievement(achievementID: String?, result: @escaping FlutterResult) {
    guard ensureAuthenticated(result: result) else { return }
    guard let resolvedID = nonPlaceholder(
      achievementID ?? Bundle.main.object(forInfoDictionaryKey: "SudokuAchievementFirstWin") as? String
    ) else {
      result(FlutterError(code: "not_configured", message: "Replace the achievement ID placeholder.", details: nil))
      return
    }

    let achievement = GKAchievement(identifier: resolvedID)
    achievement.percentComplete = 100
    achievement.showsCompletionBanner = true
    GKAchievement.report([achievement]) { error in
      DispatchQueue.main.async {
        if let error {
          result(FlutterError(code: "achievement_submit_failed", message: error.localizedDescription, details: nil))
        } else {
          result(true)
        }
      }
    }
  }

  private func requestIdentityVerification(result: @escaping FlutterResult) {
    guard ensureAuthenticated(result: result) else { return }
    GKLocalPlayer.local.fetchItems(forIdentityVerificationSignature:) {
      publicKeyURL,
      signature,
      salt,
      timestamp,
      error in
      DispatchQueue.main.async {
        if let error {
          result(FlutterError(code: "identity_verification_failed", message: error.localizedDescription, details: nil))
          return
        }
        guard let publicKeyURL, let signature, let salt else {
          result(FlutterError(code: "identity_verification_incomplete", message: nil, details: nil))
          return
        }
        result([
          "platform": "game_center",
          "playerId": GKLocalPlayer.local.gamePlayerID,
          "publicKeyUrl": publicKeyURL.absoluteString,
          "signature": signature.base64EncodedString(),
          "salt": salt.base64EncodedString(),
          "timestamp": timestamp,
          "bundleId": Bundle.main.bundleIdentifier ?? "",
        ])
      }
    }
  }

  private func nonPlaceholder(_ value: String?) -> String? {
    guard let value, !value.isEmpty, !value.hasPrefix("REPLACE_") else { return nil }
    return value
  }

  private func topViewController() -> UIViewController? {
    let root = connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }
      .first(where: { $0.isKeyWindow })?
      .rootViewController

    var current = root
    while true {
      if let presented = current?.presentedViewController {
        current = presented
      } else if let navigation = current as? UINavigationController {
        current = navigation.visibleViewController
      } else if let tab = current as? UITabBarController {
        current = tab.selectedViewController
      } else {
        return current
      }
    }
  }
}
