extension KeychainKey {
    /// Creates a ``KeychainKey`` for a generic-password item.
    ///
    /// A convenience factory that omits the optional `label` and `comment` metadata
    /// fields, which are not required for most use cases.
    ///
    /// - Parameters:
    ///   - service: The service name that groups related items (e.g., your app's bundle ID).
    ///   - account: The account identifier.
    ///   - accessGroup: The access group for sharing across apps. Defaults to `nil`.
    ///   - accessibility: Controls when the item is accessible. Defaults to ``KeychainAccessibility/whenUnlocked``.
    ///   - isSynchronizable: Pass `true` to sync this item via iCloud Keychain. Defaults to `false`.
    /// - Returns: A ``KeychainKey`` identifying the specified keychain item.
    ///
    /// ```swift
    /// let key = KeychainKey<String>.genericPassword(
    ///     service: "com.example.app",
    ///     account: "api-key"
    /// )
    /// ```
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
