import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct SwiftyChainMacrosPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        KeychainKeyMacro.self,
        KeychainItemMacro.self,
        KeychainScopeMacro.self,
    ]
}
