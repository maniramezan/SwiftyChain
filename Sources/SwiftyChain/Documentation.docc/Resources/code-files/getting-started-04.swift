import OSLog
import SwiftyChain

struct Settings {
    @DefaultedKeychainStorage("api-token", service: "com.example.myapp", defaultValue: "")
    var token: String
}

var settings = Settings()
let logger = Logger(subsystem: "com.example.myapp", category: "Keychain")

// Write
settings.token = "sk-new-token"

// Read
logger.debug("Token is configured: \(!settings.token.isEmpty, privacy: .public)")

// Check for errors via the projected value
if let error = settings.$token {
    logger.error("Keychain operation failed: \(error.logName, privacy: .public)")
}

private extension KeychainError {
    var logName: String {
        switch self {
        case .itemNotFound:
            "itemNotFound"
        case .duplicateItem:
            "duplicateItem"
        case .authenticationFailed:
            "authenticationFailed"
        case .userPresenceRequired:
            "userPresenceRequired"
        case .unexpectedData:
            "unexpectedData"
        case .encodingFailed:
            "encodingFailed"
        case .decodingFailed:
            "decodingFailed"
        case .operationFailed:
            "operationFailed"
        case .accessGroupDenied:
            "accessGroupDenied"
        case .platformUnsupported:
            "platformUnsupported"
        }
    }
}
