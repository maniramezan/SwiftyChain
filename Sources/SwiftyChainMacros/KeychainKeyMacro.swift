import SwiftSyntax
import SwiftSyntaxMacros

public struct KeychainKeyMacro: ExpressionMacro {
    public static func expansion(
        of node: some FreestandingMacroExpansionSyntax,
        in context: some MacroExpansionContext
    ) throws -> ExprSyntax {
        let arguments = node.arguments
        validateRequiredStringLiteral("service", in: arguments, node: node, context: context)
        validateRequiredStringLiteral("account", in: arguments, node: node, context: context)
        validateOptionalStringLiteral("accessGroup", in: arguments, node: node, context: context)

        let accessibility = arguments.expressionText(named: "accessibility", default: ".whenUnlocked")
        let isSynchronizable = arguments.expressionText(named: "isSynchronizable", default: "false")
        if isSynchronizable == "true" && accessibility.contains("ThisDeviceOnly") {
            context.diagnose(
                node,
                "'ThisDeviceOnly' accessibility and isSynchronizable: true are mutually exclusive"
            )
        }

        let expansion = """
            KeychainKey(
                service: \(arguments.expressionText(named: "service", default: "\"\"")),
                account: \(arguments.expressionText(named: "account", default: "\"\"")),
                accessGroup: \(arguments.expressionText(named: "accessGroup", default: "nil")),
                accessibility: \(accessibility),
                isSynchronizable: \(isSynchronizable),
                label: \(arguments.expressionText(named: "label", default: "nil")),
                comment: \(arguments.expressionText(named: "comment", default: "nil"))
            )
            """
        return ExprSyntax(stringLiteral: expansion)
    }

    private static func validateRequiredStringLiteral(
        _ name: String,
        in arguments: LabeledExprListSyntax,
        node: some FreestandingMacroExpansionSyntax,
        context: some MacroExpansionContext
    ) {
        guard let value = arguments.stringLiteral(named: name) else {
            context.diagnose(node, "\(name) must be a string literal")
            return
        }
        if value.isEmpty {
            context.diagnose(node, "\(name) must be a non-empty string literal")
        }
    }

    private static func validateOptionalStringLiteral(
        _ name: String,
        in arguments: LabeledExprListSyntax,
        node: some FreestandingMacroExpansionSyntax,
        context: some MacroExpansionContext
    ) {
        guard arguments.expression(named: name) != nil else { return }
        guard let value = arguments.stringLiteral(named: name) else {
            context.diagnose(node, "\(name) must be a string literal when provided")
            return
        }
        if value.isEmpty {
            context.diagnose(node, "\(name) must be a non-empty string literal when provided")
        }
    }
}
