#if !canImport(OSLog)
    import SwiftyChain
    import Testing

    @Test
    func publicValuesAreLoggedVerbatim() {
        let message: SwiftyChainLogMessage = "count=\(3, privacy: .public) name=\("save", privacy: .public)"

        #expect(message.rendered == "count=3 name=save")
    }

    @Test
    func privateValuesAreRedacted() {
        let message: SwiftyChainLogMessage = "account=\("alice", privacy: .private) other=\("bob")"

        #expect(message.rendered == "account=<private> other=<private>")
    }

    @Test
    func hashedValuesHideTheValueButStayStableWithinAProcess() {
        let first: SwiftyChainLogMessage = "service=\("com.example.secret", privacy: .private(mask: .hash))"
        let second: SwiftyChainLogMessage = "service=\("com.example.secret", privacy: .private(mask: .hash))"
        let other: SwiftyChainLogMessage = "service=\("com.example.other", privacy: .private(mask: .hash))"

        #expect(!first.rendered.contains("com.example.secret"))
        #expect(first.rendered.hasPrefix("service=<mask.hash: '"))
        #expect(first.rendered == second.rendered)
        #expect(first.rendered != other.rendered)
    }

    @Test
    func staticStringsAreLoggedVerbatim() {
        let operation: StaticString = "save"
        let message: SwiftyChainLogMessage = "\(operation) started"

        #expect(message.rendered == "save started")
    }
#endif
