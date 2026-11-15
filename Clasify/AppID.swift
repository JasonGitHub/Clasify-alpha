/// The app's bundle ID (CLA-112, Jason 17:51 JST 11-15). The Xcode project's
/// `PRODUCT_BUNDLE_IDENTIFIER` must be the same. The Keychain service and the log subsystem
/// come from it. Settings use `UserDefaults.standard`, whose domain is the bundle ID.
enum AppID {
    static let bundle = "com.cappyai.mypod"
}
