import OSLog
import SwiftyChain

struct Settings {
    @KeychainStorage("api-token", service: "com.example.myapp")
    var token: String?
}

let settings = Settings()
let logger = Logger(subsystem: "com.example.myapp", category: "Keychain")

// Write
settings.token = "sk-new-token"

// Read
logger.debug("Token is configured: \(settings.token != nil, privacy: .public)")

// Delete
settings.token = nil

// Check for errors via the projected value
if let error = settings.$token {
    logger.error("Keychain operation failed: \(error.logName, privacy: .public)")
}

extension KeychainError {
    fileprivate var logName: String {
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
