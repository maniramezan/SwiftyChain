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

        return [
            """
            fileprivate static let _keychainScopeService = \(raw: arguments.expressionText(named: "service", default: "\"\""))
            """,
            // String? annotation is required: bare `nil` has no type context and won't compile.
            """
            fileprivate static let _keychainScopeAccessGroup: String? = \(raw: arguments.expressionText(named: "accessGroup", default: "nil"))
            """,
            """
            static func deleteAll() async throws {
                try await Keychain.shared.deleteAll(
                    service: Self._keychainScopeService,
                    accessGroup: Self._keychainScopeAccessGroup
                )
            }
            """,
        ]
    }

}
