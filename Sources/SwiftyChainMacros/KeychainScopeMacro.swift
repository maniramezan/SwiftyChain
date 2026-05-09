import SwiftSyntax
import SwiftSyntaxMacros

public struct KeychainScopeMacro: MemberMacro, PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let arguments = node.arguments?.as(LabeledExprListSyntax.self) else {
            context.diagnose(node, "@KeychainScope requires a service string literal")
            return []
        }
        guard let service = arguments.stringLiteral(named: "service"), !service.isEmpty else {
            context.diagnose(node, "service must be a non-empty string literal")
            return []
        }

        return [
            """
            static let shared = Self()
            """,
            """
            func deleteAll() async throws {
                try await Keychain.shared.deleteAll(
                    service: \(raw: arguments.expressionText(named: "service", default: "\"\"")),
                    accessGroup: \(raw: arguments.expressionText(named: "accessGroup", default: "nil"))
                )
            }
            """,
        ]
    }

    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        []
    }
}
