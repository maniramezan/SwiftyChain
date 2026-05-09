#if Macros
    @freestanding(expression)
    public macro keychainKey<Value: KeychainStorable>(
        service: String,
        account: String,
        accessGroup: String? = nil,
        accessibility: KeychainAccessibility = .whenUnlocked,
        isSynchronizable: Bool = false,
        label: String? = nil,
        comment: String? = nil
    ) -> KeychainKey<Value> = #externalMacro(module: "SwiftyChainMacros", type: "KeychainKeyMacro")

    @attached(accessor)
    @attached(peer, names: prefixed(_), arbitrary)
    public macro KeychainItem(
        service: String? = nil,
        account: String,
        accessGroup: String? = nil,
        accessibility: KeychainAccessibility = .whenUnlocked,
        isSynchronizable: Bool = false,
        label: String? = nil,
        comment: String? = nil
    ) = #externalMacro(module: "SwiftyChainMacros", type: "KeychainItemMacro")

    @attached(member, names: arbitrary)
    @attached(peer, names: arbitrary)
    public macro KeychainScope(
        service: String,
        accessGroup: String? = nil
    ) = #externalMacro(module: "SwiftyChainMacros", type: "KeychainScopeMacro")
#endif
