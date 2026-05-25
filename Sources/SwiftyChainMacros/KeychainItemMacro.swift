import Foundation
import SwiftSyntax
import SwiftSyntaxMacros

public struct KeychainItemMacro: AccessorMacro, PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingAccessorsOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [AccessorDeclSyntax] {
        guard let variable = declaration.as(VariableDeclSyntax.self),
            let binding = variable.bindings.first,
            let identifier = binding.pattern.as(IdentifierPatternSyntax.self),
            let typeAnnotation = binding.typeAnnotation
        else {
            context.diagnose(declaration, "@KeychainItem can only be applied to a variable declaration")
            return []
        }

        let name = identifier.identifier.text
        let type = typeAnnotation.type.trimmedDescription
        let loadCall =
            isOptional(type)
            ? "try await Keychain.shared.loadIfPresent(key: Self._\(name)Key)"
            : "try await Keychain.shared.load(key: Self._\(name)Key)"

        return [
            """
            get async throws {
                \(raw: loadCall)
            }
            """
        ]
    }

    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let variable = declaration.as(VariableDeclSyntax.self),
            let binding = variable.bindings.first,
            let identifier = binding.pattern.as(IdentifierPatternSyntax.self),
            let typeAnnotation = binding.typeAnnotation
        else {
            context.diagnose(declaration, "@KeychainItem requires a typed variable declaration")
            return []
        }

        let arguments = node.arguments?.as(LabeledExprListSyntax.self)
        let account = arguments?.unlabeledExpressionText(default: "\"\"") ?? "\"\""
        if arguments?.unlabeledStringLiteral()?.isEmpty == true {
            context.diagnose(node, "account must be a non-empty string literal")
        }
        if arguments?.stringLiteral(named: "service")?.isEmpty == true {
            context.diagnose(node, "service must be a non-empty string literal")
        }

        let scope = enclosingScope(in: context)
        // `service` resolution: prefer explicit arg, then scope reference, then error.
        // We reference the scope via `Self._keychainScopeService` rather than inlining
        // the literal because the parent-chain traversal in the real macro plugin may
        // not always be available. `Self` is safe here because the key is emitted as a
        // computed property (not a stored property), so Swift's covariant-Self
        // restriction does not apply.
        let explicitService = arguments?.expressionText(named: "service", default: "") ?? ""
        let service: String
        if !explicitService.isEmpty {
            service = explicitService
        } else if scope != nil {
            service = "Self._keychainScopeService"
        } else {
            context.diagnose(node, "service is required unless the enclosing type uses @KeychainScope")
            service = "\"\""
        }

        let name = identifier.identifier.text
        let type = typeAnnotation.type.trimmedDescription
        let valueType = wrappedValueType(from: type)
        let setterName = "set\(name.prefix(1).uppercased())\(name.dropFirst())"
        let defaultAccessGroup = scope == nil ? "nil" : "Self._keychainScopeAccessGroup"
        let accessGroup =
            arguments?.expressionText(named: "accessGroup", default: defaultAccessGroup)
            ?? defaultAccessGroup
        let accessibility =
            arguments?.expressionText(named: "accessibility", default: ".whenUnlocked") ?? ".whenUnlocked"
        let isSynchronizable = arguments?.expressionText(named: "isSynchronizable", default: "false") ?? "false"
        let label = arguments?.expressionText(named: "label", default: "nil") ?? "nil"
        let comment = arguments?.expressionText(named: "comment", default: "nil") ?? "nil"

        return [
            // Computed property (not stored) so that `Self._keychainScopeService` and
            // `Self._keychainScopeAccessGroup` are legal in both structs and classes.
            // Swift only restricts covariant `Self` in stored-property initialisers.
            """
            private static var _\(raw: name)Key: KeychainKey<\(raw: valueType)> {
                KeychainKey<\(raw: valueType)>(
                    service: \(raw: service),
                    account: \(raw: account),
                    accessGroup: \(raw: accessGroup),
                    accessibility: \(raw: accessibility),
                    isSynchronizable: \(raw: isSynchronizable),
                    label: \(raw: label),
                    comment: \(raw: comment)
                )
            }
            """,
            setterMethod(name: setterName, type: type, keyName: name),
        ]
    }

    // `context.lexicalContext` is the correct way to walk enclosing scopes in the
    // real macro plugin — `.parent` traversal is unreliable in that context.
    private static func enclosingScope(in context: some MacroExpansionContext) -> ScopeValues? {
        for node in context.lexicalContext {
            if let attributes = node.as(ClassDeclSyntax.self)?.attributes,
                let scope = scopeValues(from: attributes)
            {
                return scope
            }
            if let attributes = node.as(StructDeclSyntax.self)?.attributes,
                let scope = scopeValues(from: attributes)
            {
                return scope
            }
            if let attributes = node.as(EnumDeclSyntax.self)?.attributes,
                let scope = scopeValues(from: attributes)
            {
                return scope
            }
        }
        return nil
    }

    private static func scopeValues(from attributes: AttributeListSyntax) -> ScopeValues? {
        for element in attributes {
            guard let attribute = element.as(AttributeSyntax.self),
                attribute.attributeName.trimmedDescription == "KeychainScope",
                let arguments = attribute.arguments?.as(LabeledExprListSyntax.self),
                let service = arguments.stringLiteral(named: "service"),
                !service.isEmpty
            else {
                continue
            }

            return ScopeValues(
                service: service,
                accessGroup: arguments.expressionText(named: "accessGroup", default: "nil")
            )
        }

        return nil
    }

    private struct ScopeValues {
        let service: String
        let accessGroup: String
    }

    private static func isOptional(_ type: String) -> Bool {
        type.hasSuffix("?") || (type.hasPrefix("Optional<") && type.hasSuffix(">"))
    }

    private static func wrappedValueType(from type: String) -> String {
        if type.hasSuffix("?") {
            return String(type.dropLast())
        }
        if type.hasPrefix("Optional<") && type.hasSuffix(">") {
            return String(type.dropFirst("Optional<".count).dropLast())
        }
        return type
    }

    private static func setterMethod(name: String, type: String, keyName: String) -> DeclSyntax {
        if isOptional(type) {
            return """
                func \(raw: name)(_ newValue: \(raw: type)) async throws {
                    if let newValue {
                        try await Keychain.shared.upsert(newValue, for: Self._\(raw: keyName)Key)
                    } else {
                        try await Keychain.shared.delete(key: Self._\(raw: keyName)Key)
                    }
                }
                """
        }

        return """
            func \(raw: name)(_ newValue: \(raw: type)) async throws {
                try await Keychain.shared.upsert(newValue, for: Self._\(raw: keyName)Key)
            }
            """
    }
}
