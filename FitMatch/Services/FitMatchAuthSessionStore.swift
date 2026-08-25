import AuthenticationServices
import Combine
import CryptoKit
import Foundation
import Security
import Supabase

struct FitMatchSupabaseConfiguration {
    let url: URL
    let publishableKey: String

    static func live(
        bundle: Bundle = .main,
        requiresDatabaseShadow: Bool = false
    ) -> FitMatchSupabaseConfiguration? {
        let processInfo = ProcessInfo.processInfo
        guard processInfo.environment["XCTestConfigurationFilePath"] == nil,
              !processInfo.arguments.contains("-fitmatchUITesting") else {
            return nil
        }
        if requiresDatabaseShadow {
            let enabled = bundle.object(forInfoDictionaryKey: "FitMatchDatabaseShadowEnabled") as? Bool
            guard enabled == true else { return nil }
        }
        let urlText = processInfo.environment["FITMATCH_SUPABASE_URL"]
            ?? bundle.object(forInfoDictionaryKey: "FitMatchSupabaseURL") as? String
        let key = processInfo.environment["FITMATCH_SUPABASE_PUBLISHABLE_KEY"]
            ?? bundle.object(forInfoDictionaryKey: "FitMatchSupabasePublishableKey") as? String
        guard let urlText, let url = URL(string: urlText),
              let key, key.hasPrefix("sb_publishable_") else {
            return nil
        }
        return FitMatchSupabaseConfiguration(url: url, publishableKey: key)
    }
}

enum FitMatchSupabaseClientProvider {
    static let shared: SupabaseClient? = FitMatchSupabaseConfiguration.live().map {
        SupabaseClient(supabaseURL: $0.url, supabaseKey: $0.publishableKey)
    }
}

enum FitMatchAppleSignInNonce {
    enum NonceError: LocalizedError {
        case generationFailed(OSStatus)

        var errorDescription: String? {
            switch self {
            case .generationFailed(let status):
                return "Apple 로그인 보안값을 만들지 못했습니다. (\(status))"
            }
        }
    }

    static func make(length: Int = 32) throws -> String {
        precondition(length > 0)
        let characters = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        result.reserveCapacity(length)

        while result.count < length {
            var random: UInt8 = 0
            let status = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
            guard status == errSecSuccess else {
                throw NonceError.generationFailed(status)
            }
            guard random < UInt8(characters.count) else { continue }
            result.append(characters[Int(random)])
        }
        return result
    }

    static func hashed(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

enum FitMatchAuthSessionState: Equatable {
    case loading
    case signedOut
    case signedIn(userID: UUID)
}

enum FitMatchAuthSessionError: LocalizedError {
    case notConfigured
    case missingAppleCredential
    case missingIdentityToken
    case missingNonce
    case accountDeletionFailed

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "로그인 서버 설정을 불러오지 못했습니다."
        case .missingAppleCredential:
            return "Apple 로그인 정보를 확인하지 못했습니다."
        case .missingIdentityToken:
            return "Apple 로그인 토큰을 받지 못했습니다."
        case .missingNonce:
            return "Apple 로그인 요청이 만료되었습니다. 다시 시도해 주세요."
        case .accountDeletionFailed:
            return "계정 삭제를 완료하지 못했습니다. 잠시 후 다시 시도해 주세요."
        }
    }
}

nonisolated private struct FitMatchDeleteAccountRequest: Encodable, Sendable {
    let confirmation = "DELETE_MY_FITMATCH_ACCOUNT"
}

nonisolated private struct FitMatchDeleteAccountResponse: Decodable, Sendable {
    let deleted: Bool
}

protocol FitMatchAccountDeletionServicing: Sendable {
    func deleteAccount() async throws
}

actor FitMatchSupabaseAccountDeletionService: FitMatchAccountDeletionServicing {
    private let client: SupabaseClient?

    init(client: SupabaseClient?) {
        self.client = client
    }

    func deleteAccount() async throws {
        guard let client else {
            throw FitMatchAuthSessionError.notConfigured
        }
        let response: FitMatchDeleteAccountResponse = try await client.functions.invoke(
            "delete-account",
            options: FunctionInvokeOptions(body: FitMatchDeleteAccountRequest())
        )
        guard response.deleted else {
            throw FitMatchAuthSessionError.accountDeletionFailed
        }
    }
}

@MainActor
final class FitMatchAuthSessionStore: ObservableObject {
    @Published private(set) var state: FitMatchAuthSessionState = .loading
    @Published private(set) var isSigningIn = false
    @Published private(set) var isDeletingAccount = false
    @Published private(set) var errorMessage: String?

    private let client: SupabaseClient?
    private let accountDeletionService: any FitMatchAccountDeletionServicing
    private var currentNonce: String?

    init(
        client: SupabaseClient?,
        accountDeletionService: (any FitMatchAccountDeletionServicing)? = nil
    ) {
        self.client = client
        self.accountDeletionService = accountDeletionService
            ?? FitMatchSupabaseAccountDeletionService(client: client)
    }

    convenience init() {
        self.init(client: FitMatchSupabaseClientProvider.shared)
    }

    var isAuthenticated: Bool {
        if case .signedIn = state { return true }
        return false
    }

    func observeAuthChanges() async {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-fitmatchUITesting") {
            state = .signedIn(userID: UUID())
            return
        }
        #endif

        guard let client else {
            state = .signedOut
            errorMessage = FitMatchAuthSessionError.notConfigured.localizedDescription
            return
        }

        for await change in client.auth.authStateChanges {
            guard !Task.isCancelled else { return }
            switch change.event {
            case .initialSession, .signedIn, .signedOut, .tokenRefreshed, .userUpdated:
                if let session = change.session {
                    state = .signedIn(userID: session.user.id)
                    errorMessage = nil
                } else {
                    state = .signedOut
                }
            default:
                break
            }
        }
    }

    func prepareAppleSignIn(_ request: ASAuthorizationAppleIDRequest) {
        do {
            let nonce = try FitMatchAppleSignInNonce.make()
            currentNonce = nonce
            errorMessage = nil
            request.requestedScopes = [.email]
            request.nonce = FitMatchAppleSignInNonce.hashed(nonce)
        } catch {
            currentNonce = nil
            errorMessage = error.localizedDescription
        }
    }

    func completeAppleSignIn(
        _ result: Result<ASAuthorization, Error>
    ) async {
        isSigningIn = true
        defer {
            isSigningIn = false
            currentNonce = nil
        }

        do {
            let authorization = try result.get()
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                throw FitMatchAuthSessionError.missingAppleCredential
            }
            guard let tokenData = credential.identityToken,
                  let identityToken = String(data: tokenData, encoding: .utf8) else {
                throw FitMatchAuthSessionError.missingIdentityToken
            }
            guard let currentNonce else {
                throw FitMatchAuthSessionError.missingNonce
            }
            guard let client else {
                throw FitMatchAuthSessionError.notConfigured
            }

            let session = try await client.auth.signInWithIdToken(
                credentials: OpenIDConnectCredentials(
                    provider: .apple,
                    idToken: identityToken,
                    nonce: currentNonce
                )
            )
            state = .signedIn(userID: session.user.id)
            errorMessage = nil
        } catch let error as ASAuthorizationError where error.code == .canceled {
            errorMessage = nil
        } catch {
            state = .signedOut
            errorMessage = error.localizedDescription
        }
    }

    func signOut() async {
        guard let client else {
            state = .signedOut
            return
        }
        do {
            try await client.auth.signOut()
            state = .signedOut
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    func deleteAccount() async -> Bool {
        guard !isDeletingAccount else { return false }

        isDeletingAccount = true
        errorMessage = nil
        defer { isDeletingAccount = false }

        do {
            try await accountDeletionService.deleteAccount()

            // The server has removed the auth user and all linked identities.
            // Remove the cached JWT as well because an issued JWT can otherwise
            // remain locally available until its expiry time.
            try? await client?.auth.signOut(scope: .local)
            state = .signedOut
            errorMessage = nil
            return true
        } catch {
            errorMessage = FitMatchAuthSessionError.accountDeletionFailed.localizedDescription
            return false
        }
    }
}
