import OSLog

package enum SwiftyChainLoggers {
    private static let subsystem = "dev.manman.SwiftyChain"

    package static let keychain = Logger(subsystem: subsystem, category: "Keychain")
    package static let backend = Logger(subsystem: subsystem, category: "Backend")
    package static let storage = Logger(subsystem: subsystem, category: "Storage")
    package static let observation = Logger(subsystem: subsystem, category: "Observation")
}
