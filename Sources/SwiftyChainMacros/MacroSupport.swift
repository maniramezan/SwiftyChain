import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

struct SwiftyChainMacroDiagnostic: DiagnosticMessage {
    let message: String
    let diagnosticID: MessageID
    let severity: DiagnosticSeverity

    init(_ message: String, severity: DiagnosticSeverity = .error) {
        self.message = message
        self.diagnosticID = MessageID(domain: "SwiftyChainMacros", id: message)
        self.severity = severity
    }
}

extension LabeledExprListSyntax {
    func expression(named name: String) -> ExprSyntax? {
        first { $0.label?.text == name }?.expression
    }

    func expressionText(named name: String, default defaultValue: String) -> String {
        expression(named: name)?.trimmedDescription ?? defaultValue
    }

    func stringLiteral(named name: String) -> String? {
        guard let expression = expression(named: name),
            let literal = expression.as(StringLiteralExprSyntax.self),
            literal.segments.count == 1,
            case .stringSegment(let segment)? = literal.segments.first
        else {
            return nil
        }
        return segment.content.text
    }
}

extension MacroExpansionContext {
    func diagnose(_ node: some SyntaxProtocol, _ message: String, severity: DiagnosticSeverity = .error) {
        diagnose(Diagnostic(node: Syntax(node), message: SwiftyChainMacroDiagnostic(message, severity: severity)))
    }
}
