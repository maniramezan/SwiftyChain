import OSLog
import SwiftyChain

struct SessionStore {
    @KeychainStorage("auth-token", service: "com.example.myapp")
    var authToken: String?
}

let session = SessionStore()
let logger = Logger(subsystem: "com.example.myapp", category: "Keychain")

if let error = session.$authToken {
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
