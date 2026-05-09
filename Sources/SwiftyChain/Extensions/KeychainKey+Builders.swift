extension KeychainKey {
    /// Creates a generic-password key using the default accessibility policy.
    public static func genericPassword(
        service: String,
        account: String,
        accessGroup: String? = nil,
        accessibility: KeychainAccessibility = .whenUnlocked,
        isSynchronizable: Bool = false
    ) -> Self {
        Self(
            service: service,
            account: account,
            accessGroup: accessGroup,
            accessibility: accessibility,
            isSynchronizable: isSynchronizable
        )
    }
}
