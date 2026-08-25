import Foundation
import Testing
@testable import FitMatch

struct FitMatchAuthSessionStoreTests {
    @Test func appleNonceHasExpectedLengthAndAllowedCharacters() throws {
        let nonce = try FitMatchAppleSignInNonce.make()
        let allowed = Set("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")

        #expect(nonce.count == 32)
        #expect(nonce.allSatisfy(allowed.contains))
    }

    @Test func appleNonceHashMatchesKnownSHA256Value() {
        #expect(
            FitMatchAppleSignInNonce.hashed("fitmatch")
                == "2648454804ffbe3a21a1e098b3ab3ea21eae35f09971febbd6b927f266872213"
        )
    }

    @MainActor
    @Test func accountDeletionSignsOutAfterServerSuccess() async {
        let store = FitMatchAuthSessionStore(
            client: nil,
            accountDeletionService: AccountDeletionStub(result: .success(()))
        )

        let deleted = await store.deleteAccount()

        #expect(deleted)
        #expect(store.state == .signedOut)
        #expect(store.errorMessage == nil)
        #expect(!store.isDeletingAccount)
    }

    @MainActor
    @Test func accountDeletionKeepsSessionStateAndReportsSafeErrorAfterFailure() async {
        let store = FitMatchAuthSessionStore(
            client: nil,
            accountDeletionService: AccountDeletionStub(result: .failure(.expected))
        )

        let deleted = await store.deleteAccount()

        #expect(!deleted)
        #expect(store.state == .loading)
        #expect(store.errorMessage == FitMatchAuthSessionError.accountDeletionFailed.localizedDescription)
        #expect(!store.isDeletingAccount)
    }
}

private enum AccountDeletionStubError: Error, Sendable {
    case expected
}

private actor AccountDeletionStub: FitMatchAccountDeletionServicing {
    let result: Result<Void, AccountDeletionStubError>

    init(result: Result<Void, AccountDeletionStubError>) {
        self.result = result
    }

    func deleteAccount() async throws {
        try result.get()
    }
}
