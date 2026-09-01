import AuthenticationServices
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

    /// CM-016: the production My Page action keeps server failure, successful
    /// local cleanup, and local-purge failure distinct. A server failure never
    /// claims that local data was removed; a post-server local failure exposes
    /// a truthful recovery message instead of a false deletion success.
    @MainActor
    @Test func cm016AccountDeletionActionSeparatesServerAndLocalCleanupOutcomes() async {
        let userID = UUID()

        let successfulStore = FitMatchAuthSessionStore(
            client: nil,
            accountDeletionService: AccountDeletionStub(result: .success(()))
        )
        successfulStore.applyObservedSession(userID)
        var successfulPurgeCount = 0
        var processedHistoryIDs: [UUID] = []
        let success = await FitMatchAccountDeletionAction.delete(
            authSession: successfulStore,
            deletedUserID: userID,
            purgeLocalData: { successfulPurgeCount += 1 },
            purgeProcessedHistoryIDs: { processedHistoryIDs.append($0) }
        )
        #expect(success == .deleted)
        #expect(successfulStore.state == .signedOut)
        #expect(successfulPurgeCount == 1)
        #expect(processedHistoryIDs == [userID])

        let serverFailureStore = FitMatchAuthSessionStore(
            client: nil,
            accountDeletionService: AccountDeletionStub(result: .failure(.expected))
        )
        serverFailureStore.applyObservedSession(userID)
        var serverFailurePurgeCount = 0
        let serverFailure = await FitMatchAccountDeletionAction.delete(
            authSession: serverFailureStore,
            deletedUserID: userID,
            purgeLocalData: { serverFailurePurgeCount += 1 },
            purgeProcessedHistoryIDs: { _ in Issue.record("server failure must not purge history IDs") }
        )
        guard case .serverDeletionFailed(let serverMessage) = serverFailure else {
            Issue.record("CM-016 server failure did not reach the production failure outcome")
            return
        }
        #expect(serverMessage.isEmpty == false)
        #expect(serverFailureStore.state == .signedIn(userID: userID))
        #expect(serverFailurePurgeCount == 0)

        let localFailureStore = FitMatchAuthSessionStore(
            client: nil,
            accountDeletionService: AccountDeletionStub(result: .success(()))
        )
        localFailureStore.applyObservedSession(userID)
        let localFailure = await FitMatchAccountDeletionAction.delete(
            authSession: localFailureStore,
            deletedUserID: userID,
            purgeLocalData: { throw AccountDeletionStubError.expected },
            purgeProcessedHistoryIDs: { _ in Issue.record("local purge failure must not clear comparison sync state") }
        )
        guard case .localPurgeFailed(let localMessage) = localFailure else {
            Issue.record("CM-016 local failure did not reach the production recovery outcome")
            return
        }
        #expect(localFailureStore.state == .signedOut)
        #expect(localMessage.contains("안전하게 정리하지 못했어요"))
    }

    /// EN-007's Apple sheet itself remains a system-owned physical interaction,
    /// but every callback branch after that sheet returns must use the real
    /// production session action.
    @MainActor
    @Test func appleSessionActionPreservesSuccessFailureLogoutAndReloginTransitions() async {
        let userA = UUID()
        let userB = UUID()
        let service = AuthSessionStub(
            signInResults: [.success(userA), .failure(.transport), .success(userB)]
        )
        let store = FitMatchAuthSessionStore(
            client: nil,
            accountDeletionService: AccountDeletionStub(result: .success(())),
            authSessionService: service
        )

        // This mirrors the live initial auth stream before Apple is presented.
        store.applyObservedSession(nil)
        #expect(store.state == .signedOut)

        // The system callback is the production entry point. A user cancel is
        // neither a token-exchange failure nor a stale signed-in state: it
        // keeps the signed-out route, clears a prior visible error, and never
        // calls the auth network boundary.
        await store.completeAppleSignIn(.failure(ASAuthorizationError(.canceled)))
        #expect(store.state == .signedOut)
        #expect(store.errorMessage == nil)
        #expect(!store.isSigningIn)
        #expect(service.signInCallCount == 0)

        await store.completeAppleSignIn(identityToken: "token-a", nonce: "nonce-a")
        #expect(store.state == .signedIn(userID: userA))
        #expect(store.errorMessage == nil)

        await store.signOut()
        #expect(store.state == .signedOut)
        #expect(store.errorMessage == nil)

        // A system callback without a usable token must fail closed before the
        // remote exchange, leaving the user in the signed-out route.
        await store.completeAppleSignIn(identityToken: nil, nonce: "nonce-a")
        #expect(store.state == .signedOut)
        #expect(store.errorMessage == FitMatchAuthSessionError.missingIdentityToken.localizedDescription)
        #expect(service.signInCallCount == 1)

        // A real exchange failure is likewise recoverable through the same
        // production action, followed by a new account's successful login.
        await store.completeAppleSignIn(identityToken: "token-failure", nonce: "nonce-failure")
        #expect(store.state == .signedOut)
        #expect(store.errorMessage == AuthSessionStubError.transport.localizedDescription)

        await store.completeAppleSignIn(identityToken: "token-b", nonce: "nonce-b")
        #expect(store.state == .signedIn(userID: userB))
        #expect(store.errorMessage == nil)
        #expect(service.signInCallCount == 3)
        #expect(service.signOutCallCount == 1)
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

private enum AuthSessionStubError: LocalizedError, Sendable {
    case transport

    var errorDescription: String? {
        switch self {
        case .transport:
            return "로그인 서버에 연결하지 못했습니다."
        }
    }
}

@MainActor
private final class AuthSessionStub: FitMatchAuthSessionServicing {
    private var signInResults: [Result<UUID, AuthSessionStubError>]
    private(set) var signInCallCount = 0
    private(set) var signOutCallCount = 0

    init(signInResults: [Result<UUID, AuthSessionStubError>]) {
        self.signInResults = signInResults
    }

    func signInWithApple(identityToken: String, nonce: String) async throws -> UUID {
        signInCallCount += 1
        guard !signInResults.isEmpty else {
            throw AuthSessionStubError.transport
        }
        return try signInResults.removeFirst().get()
    }

    func signOut() async throws {
        signOutCallCount += 1
    }
}
