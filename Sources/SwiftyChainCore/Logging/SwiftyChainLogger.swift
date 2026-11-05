#if canImport(OSLog)
    import OSLog

    package typealias SwiftyChainLogger = Logger
#else
    import Logging

    /// A swift-log backed logger with the `os.Logger` call shape used across SwiftyChain.
    ///
    /// Interpolations accept the same `privacy:` arguments as `os.Logger`. Private values
    /// are replaced by a per-process hash, mirroring os_log's salted `.private(mask: .hash)`,
    /// so logs can correlate events without exposing identifiers.
    package struct SwiftyChainLogger: Sendable {
        private let logger: Logging.Logger

        package init(subsystem: String, category: String) {
            self.logger = Logging.Logger(label: "\(subsystem).\(category)")
        }

        package func debug(_ message: SwiftyChainLogMessage) {
            logger.debug("\(message.rendered)")
        }

        package func info(_ message: SwiftyChainLogMessage) {
            logger.info("\(message.rendered)")
        }

        package func notice(_ message: SwiftyChainLogMessage) {
            logger.notice("\(message.rendered)")
        }

        package func error(_ message: SwiftyChainLogMessage) {
            logger.error("\(message.rendered)")
        }

        package func fault(_ message: SwiftyChainLogMessage) {
            logger.critical("\(message.rendered)")
        }
    }

    /// How an interpolated value appears in a ``SwiftyChainLogMessage``.
    package enum SwiftyChainLogPrivacy: Sendable {
        case `public`
        case `private`
        case privateHashed

        package enum Mask: Sendable {
            case hash
        }

        package static func `private`(mask: Mask) -> SwiftyChainLogPrivacy {
            .privateHashed
        }
    }

    /// A log message whose interpolations are redacted according to their privacy.
    package struct SwiftyChainLogMessage: ExpressibleByStringInterpolation, Sendable {
        package struct StringInterpolation: StringInterpolationProtocol {
            fileprivate var output = ""

            package init(literalCapacity: Int, interpolationCount: Int) {
                output.reserveCapacity(literalCapacity)
            }

            package mutating func appendLiteral(_ literal: String) {
                output += literal
            }

            package mutating func appendInterpolation(_ value: StaticString) {
                output += value.description
            }

            package mutating func appendInterpolation<Value>(
                _ value: Value,
                privacy: SwiftyChainLogPrivacy = .private
            ) {
                let text = String(describing: value)
                switch privacy {
                case .public:
                    output += text
                case .private:
                    output += "<private>"
                case .privateHashed:
                    var hasher = Hasher()
                    hasher.combine(text)
                    let digest = UInt64(bitPattern: Int64(hasher.finalize()))
                    output += "<mask.hash: '\(String(digest, radix: 16))'>"
                }
            }
        }

        package let rendered: String

        package init(stringLiteral value: String) {
            self.rendered = value
        }

        package init(stringInterpolation: StringInterpolation) {
            self.rendered = stringInterpolation.output
        }
    }
#endif

package enum SwiftyChainLoggers {
    private static let subsystem = "dev.manman.SwiftyChain"

    package static let keychain = SwiftyChainLogger(subsystem: subsystem, category: "Keychain")
    package static let backend = SwiftyChainLogger(subsystem: subsystem, category: "Backend")
    package static let storage = SwiftyChainLogger(subsystem: subsystem, category: "Storage")
    package static let observation = SwiftyChainLogger(subsystem: subsystem, category: "Observation")
}
