import XCTest
@testable import TomatoBar

final class CredentialStoreTests: XCTestCase {
    func testKeychainRoundTripUpdateAndDelete() throws {
        let store = KeychainCredentialStore(
            service: "com.github.ivoronin.TomatoBarTests.\(UUID().uuidString)",
            account: "todoist-test-token"
        )
        defer {
            try? store.deleteToken()
        }

        XCTAssertNil(try store.loadToken())

        try store.saveToken(" first-token \n")
        XCTAssertEqual(try store.loadToken(), "first-token")

        try store.saveToken("second-token")
        XCTAssertEqual(try store.loadToken(), "second-token")

        try store.deleteToken()
        XCTAssertNil(try store.loadToken())
    }

    func testEmptyTokenIsRejected() {
        let store = KeychainCredentialStore(
            service: "com.github.ivoronin.TomatoBarTests.\(UUID().uuidString)",
            account: "todoist-test-token"
        )

        XCTAssertThrowsError(try store.saveToken(" \n")) { error in
            XCTAssertEqual(error as? CredentialStoreError, .emptyToken)
        }
    }
}
