#if os(Linux)
    import Foundation

    /// Runs a program and returns its exit status, or `-1` when it didn't exit normally.
    ///
    /// `posix_spawn` and `waitpid` are used directly because `Process.waitUntilExit()`
    /// never returns in this test runner once libsecret is loaded.
    func runCommand(_ arguments: [String]) throws -> Int32 {
        var argv: [UnsafeMutablePointer<CChar>?] = arguments.map { strdup($0) } + [nil]
        defer {
            for argument in argv {
                free(argument)
            }
        }
        var pid: pid_t = 0
        let spawned = posix_spawnp(&pid, arguments[0], nil, nil, &argv, environ)
        guard spawned == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: spawned) ?? .EINVAL)
        }
        var status: Int32 = 0
        while waitpid(pid, &status, 0) == -1, errno == EINTR {}
        // WIFEXITED and WEXITSTATUS are macros Swift can't import.
        guard status & 0x7f == 0 else { return -1 }
        return (status >> 8) & 0xff
    }
#endif
