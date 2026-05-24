import OSLog

internal enum SwiftyChainLoggers {
    private static let subsystem = "dev.manman.SwiftyChain"

    static let keychain = Logger(subsystem: subsystem, category: "Keychain")
    static let backend = Logger(subsystem: subsystem, category: "Backend")
    static let storage = Logger(subsystem: subsystem, category: "Storage")
    static let observation = Logger(subsystem: subsystem, category: "Observation")
}
