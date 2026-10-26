import UIKit
import Flutter
import flutter_local_notifications

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var themeObserver: NSObjectProtocol?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self
    }

    let launched = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    applySavedTheme()
    // SharedPreferences is the existing theme source for Flutter and native views.
    themeObserver = NotificationCenter.default.addObserver(
      forName: UserDefaults.didChangeNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      self?.applySavedTheme()
    }
    return launched
  }

  private func applySavedTheme() {
    let style: UIUserInterfaceStyle =
      UserDefaults.standard.string(forKey: "flutter.themeData") == "darkMode" ? .dark : .light
    if window?.overrideUserInterfaceStyle != style {
      window?.overrideUserInterfaceStyle = style
    }
  }

  deinit {
    if let themeObserver {
      NotificationCenter.default.removeObserver(themeObserver)
    }
  }
}
