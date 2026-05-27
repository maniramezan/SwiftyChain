import SwiftSyntax
import SwiftSyntaxMacros

public struct KeychainScopeMacro: MemberMacro {
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

        let keychainExpression = arguments.expressionText(named: "keychain", default: "Keychain.shared")

        return [
            """
            private static let _keychainScopeService = \(raw: arguments.expressionText(named: "service", default: "\"\""))
            """,
            // String? annotation is required: bare `nil` has no type context and won't compile.
            """
            private static let _keychainScopeAccessGroup: String? = \(raw: arguments.expressionText(named: "accessGroup", default: "nil"))
            """,
            """
            private static var _keychainScopeInstance: any KeychainProtocol { \(raw: keychainExpression) }
            """,
            """
            static func deleteAll() async throws {
                try await Self._keychainScopeInstance.deleteAll(
                    service: Self._keychainScopeService,
                    accessGroup: Self._keychainScopeAccessGroup
                )
            }
            """,
        ]
    }

}
