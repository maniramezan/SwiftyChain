import SwiftUI

/// An empty app that hosts `DataProtectionIntegrationTests`, so the keychain sees the
/// entitlements of a signed app instead of a bare test bundle.
@main
struct HostApp: App {
    var body: some Scene {
        WindowGroup {
            Text("SwiftyChain keychain host")
        }
    }
}
