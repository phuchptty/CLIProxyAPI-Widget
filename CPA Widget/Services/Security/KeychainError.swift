import Foundation
import Security

struct KeychainError: LocalizedError {
    let status: OSStatus
    var errorDescription: String? {
        "Keychain access failed (\(status)). \(SecCopyErrorMessageString(status, nil) as String? ?? "Check Keychain permissions.")"
    }
}
