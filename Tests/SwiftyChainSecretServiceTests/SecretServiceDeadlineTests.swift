import SwiftyChainSecretService
import Testing

@Suite("Secret Service deadlines")
struct SecretServiceDeadlineTests {
    @Test
    func convertsTimeoutsToNanoseconds() {
        #expect(SecretServiceDeadline.nanoseconds(in: .seconds(30)) == 30_000_000_000)
        #expect(SecretServiceDeadline.nanoseconds(in: .milliseconds(1500)) == 1_500_000_000)
    }

    @Test
    func clampsNonPositiveTimeoutsToZero() {
        #expect(SecretServiceDeadline.nanoseconds(in: .zero) == 0)
        #expect(SecretServiceDeadline.nanoseconds(in: .seconds(-5)) == 0)
    }

    @Test
    func treatsUnrepresentableTimeoutsAsNoDeadline() {
        #expect(SecretServiceDeadline.nanoseconds(in: .seconds(Int64.max)) == nil)
        #expect(SecretServiceDeadline.dispatchTime(after: .seconds(Int64.max)) == .distantFuture)
    }
}
